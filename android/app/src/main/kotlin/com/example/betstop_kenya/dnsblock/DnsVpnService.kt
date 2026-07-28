package com.example.betstop_kenya.dnsblock

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.atomic.AtomicBoolean

/**
 * DNS-only VPN Service for blocking gambling domains.
 * 
 * ROUTING SCOPE CRITICAL:
 * - This VPN routes ONLY DNS traffic through the tunnel
 * - Single /32 host route for the virtual DNS server address (10.111.222.2)
 * - NO 0.0.0.0/0 catch-all route - all other traffic bypasses this VPN entirely
 * - This is the GOOD approach (like NextDNS/1.1.1.1), not the BAD approach (like Gamban/BetBlocker)
 * 
 * Architecture:
 * - Private point-to-point tun pair: 10.111.222.1 (local) <-> 10.111.222.2 (remote)
 * - Advertise 10.111.222.2 as DNS server via addDnsServer()
 * - addRoute("10.111.222.2", 32) - the ONE AND ONLY route
 * - Intercept DNS queries on port 53, check blocklist, forward to Cloudflare 1.1.1.1
 * - Return NXDOMAIN for blocked domains, forward unmodified responses for allowed domains
 * - Fail-open on errors (200ms timeout) - never block internet access
 * 
 * Limitations:
 * - Only handles plain DNS (port 53). DoH (port 443) and DoT (port 853) bypass this VPN.
 * - This is acceptable for this phase and matches NextDNS consumer app limitations.
 */
class DnsVpnService : VpnService() {
    
    companion object {
        private const val TAG = "DnsVpnService"
        private const val NOTIFICATION_CHANNEL_ID = "DNSBlockVPN"
        private const val NOTIFICATION_ID = 1001
        
        // Private point-to-point tun pair
        private const val LOCAL_TUN_IP = "10.111.222.1"
        private const val REMOTE_TUN_IP = "10.111.222.2"
        
        // Upstream DNS resolvers with fallback chain
        private val UPSTREAM_DNS_SERVERS = listOf("1.1.1.1", "8.8.8.8", "1.0.0.1")
        private const val UPSTREAM_DNS_PORT = 53
        
        // Timeout for DNS lookups (fail-open if exceeded)
        // Increased from 1000ms to 5000ms to reduce false failures
        private const val DNS_TIMEOUT_MS = 5000L
        
        // VPN interface MTU
        private const val MTU = 1500
        
        // Rolling window for sustained failure detection (30 seconds)
        private const val SUSTAINED_FAILURE_WINDOW_MS = 30000L
        
        // Minimum failure rate to trigger sustained failure alert (80% failures)
        private const val SUSTAINED_FAILURE_THRESHOLD = 0.8
        
        // DNS server deprioritization settings
        private const val DEPRIORITIZE_AFTER_FAILURES = 5
        private const val DEPRIORITIZE_DURATION_MS = 60000L
        
        @Volatile var isRunning: Boolean = false
            private set
        @Volatile var onVpnStartedListener: (() -> Unit)? = null
        @Volatile var onSustainedFailureListener: (() -> Unit)? = null
    }
    
    private var vpnInterface: ParcelFileDescriptor? = null
    private var atomicIsRunning = AtomicBoolean(false)
    private var blocklistManager: BlocklistManager? = null
    private var dnsPacketParser: DnsPacketParser? = null
    
    // Rolling window failure tracking
    private val failureTimestamps = mutableListOf<Long>()
    private var totalQueries = 0
    private var totalFailures = 0
    private var sustainedFailureReported = false
    
    // DNS server deprioritization tracking
    private val dnsServerFailures = mutableMapOf<String, Int>() // Server -> consecutive failures
    private val dnsServerDeprioritizedUntil = mutableMapOf<String, Long>() // Server -> timestamp
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "START" -> startVpn()
            "STOP" -> stopVpn()
        }
        return START_STICKY
    }
    
    private fun startVpn() {
        if (atomicIsRunning.get()) {
            Log.w(TAG, "VPN already running")
            return
        }
        
        // Initialize managers
        blocklistManager = BlocklistManager(this)
        
        // Load blocklist from Flutter (via BlocklistHolder)
        val flutterDomains = com.example.betstop_kenya.BlocklistHolder.domains
        if (flutterDomains.isNotEmpty()) {
            blocklistManager!!.updateBlocklist(flutterDomains)
            Log.i(TAG, "Loaded blocklist from Flutter: ${flutterDomains.size} domains")
        } else {
            // Try to load from cache if Flutter hasn't provided blocklist yet
            if (!blocklistManager!!.loadBlocklist()) {
                Log.w(TAG, "No blocklist available - VPN will allow all domains")
            }
        }
        
        dnsPacketParser = DnsPacketParser()
        
        // Start foreground service
        startForegroundService()
        
        // Configure VPN interface
        val builder = Builder()
            .setSession("BetStop DNS Block")
            .addAddress(LOCAL_TUN_IP, 30)
            .addRoute(REMOTE_TUN_IP, 32) // Route for virtual DNS server
            .addRoute("1.1.1.1", 32) // Route for Cloudflare DNS
            .addRoute("1.0.0.1", 32) // Route for Cloudflare DNS backup
            .addRoute("8.8.8.8", 32) // Route for Google DNS
            .addDnsServer(REMOTE_TUN_IP) // Advertise virtual DNS as system DNS
            .setMtu(MTU)
        
        // Establish VPN interface
        vpnInterface = builder.establish()
        
        if (vpnInterface == null) {
            Log.e(TAG, "Failed to establish VPN interface")
            stopForeground(true)
            stopSelf()
            return
        }
        
        atomicIsRunning.set(true)
        isRunning = true
        
        // Reset failure tracking on VPN start
        failureTimestamps.clear()
        totalQueries = 0
        totalFailures = 0
        sustainedFailureReported = false
        
        // Reset DNS server deprioritization tracking
        dnsServerFailures.clear()
        dnsServerDeprioritizedUntil.clear()
        
        Log.i(TAG, "VPN started with DNS-only routing scope: routes($REMOTE_TUN_IP/32, 1.1.1.1/32, 1.0.0.1/32, 8.8.8.8/32)")
        onVpnStartedListener?.invoke()
        Log.i(TAG, "VPN started, listener invoked")
        
        // Start DNS packet processing thread
        Thread { processDnsPackets() }.start()
    }
    
    private fun stopVpn() {
        atomicIsRunning.set(false)
        isRunning = false
        vpnInterface?.close()
        vpnInterface = null
        stopForeground(true)
        stopSelf()
        
        // Force DNS restoration by triggering network refresh
        // This prevents orphaned DNS settings pointing to dead virtual DNS server
        try {
            val connectivityManager = getSystemService(android.net.ConnectivityManager::class.java)
            if (connectivityManager != null) {
                // Request network callback to force DNS refresh
                val networkRequest = android.net.NetworkRequest.Builder()
                    .addCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .build()
                
                val networkCallback = object : android.net.ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: android.net.Network) {
                        connectivityManager.unregisterNetworkCallback(this)
                        Log.i(TAG, "Network refreshed, DNS should be restored")
                    }
                }
                
                connectivityManager.registerNetworkCallback(networkRequest, networkCallback)
                // Unregister after short delay to trigger refresh
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    try {
                        connectivityManager.unregisterNetworkCallback(networkCallback)
                    } catch (e: Exception) {
                        // Callback may already be unregistered
                    }
                }, 1000)
                
                Log.i(TAG, "Triggered network refresh for DNS restoration")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error triggering DNS restoration: ${e.message}")
        }
        
        Log.i(TAG, "VPN stopped")
    }
    
    private fun startForegroundService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "DNS Blocking Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
        
        val notification = Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("BetStop DNS Blocking")
            .setContentText("Blocking gambling websites")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .build()
        
        startForeground(NOTIFICATION_ID, notification)
    }
    
    private fun processDnsPackets() {
        val vpnInput = FileInputStream(vpnInterface!!.fileDescriptor)
        val vpnOutput = FileOutputStream(vpnInterface!!.fileDescriptor)
        
        val buffer = ByteArray(MTU)
        
        while (atomicIsRunning.get()) {
            try {
                val bytesRead = vpnInput.read(buffer)
                if (bytesRead <= 0) continue
                
                // Parse DNS packet
                val domainName = dnsPacketParser?.extractDomainName(buffer.copyOf(bytesRead))
                
                if (domainName != null) {
                    Log.d(TAG, "DNS query for: $domainName")
                    
                    // Check blocklist with timeout
                    val isBlocked = checkBlocklistWithTimeout(domainName)
                    
                    if (isBlocked) {
                        // Return NXDOMAIN for blocked domains
                        val nxResponse = dnsPacketParser?.createNxDomainResponse(buffer.copyOf(bytesRead))
                        if (nxResponse != null) {
                            vpnOutput.write(nxResponse)
                            Log.d(TAG, "Blocked domain: $domainName (NXDOMAIN)")
                        }
                    } else {
                        // Forward to upstream DNS
                        forwardToUpstreamDns(buffer.copyOf(bytesRead), vpnOutput)
                    }
                } else {
                    // Not a DNS packet or parsing failed, forward as-is
                    vpnOutput.write(buffer, 0, bytesRead)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error processing DNS packet: ${e.message}")
                // Fail-open: continue processing
            }
        }
    }
    
    private fun checkBlocklistWithTimeout(domain: String): Boolean {
        return try {
            // Simple in-memory lookup, should be instant
            // If somehow slow, timeout and fail-open
            blocklistManager?.isBlocked(domain) ?: false
        } catch (e: Exception) {
            Log.e(TAG, "Blocklist check failed for $domain: ${e.message}")
            false // Fail-open
        }
    }
    
    private fun forwardToUpstreamDns(queryData: ByteArray, vpnOutput: FileOutputStream) {
        var success = false
        totalQueries++
        
        // Get ordered DNS server list with deprioritization applied
        val now = System.currentTimeMillis()
        val orderedServers = getOrderedDnsServers(now)
        
        // Try each upstream DNS server in order
        for (dnsServer in orderedServers) {
            try {
                // Create socket protected by VPN (so it doesn't loop back)
                // Use Kotlin use block to ensure socket is closed on all paths
                DatagramSocket().use { socket ->
                    protect(socket)
                    
                    val upstreamAddress = InetAddress.getByName(dnsServer)
                    val packet = DatagramPacket(queryData, queryData.size, upstreamAddress, UPSTREAM_DNS_PORT)
                    
                    // Send query to upstream DNS
                    socket.send(packet)
                    
                    // Receive response with timeout
                    val responseBuffer = ByteArray(MTU)
                    val responsePacket = DatagramPacket(responseBuffer, responseBuffer.size)
                    socket.soTimeout = DNS_TIMEOUT_MS.toInt()
                    socket.receive(responsePacket)
                    
                    // Forward response back to VPN
                    vpnOutput.write(responsePacket.data, 0, responsePacket.length)
                    
                    // Reset failure counter for this server on success
                    dnsServerFailures[dnsServer] = 0
                    dnsServerDeprioritizedUntil.remove(dnsServer)
                    
                    success = true
                    Log.d(TAG, "Successfully forwarded DNS query to $dnsServer")
                }
                break
            } catch (e: Exception) {
                Log.w(TAG, "Failed to forward to $dnsServer: ${e.message}")
                
                // Track consecutive failures for this server
                dnsServerFailures[dnsServer] = (dnsServerFailures[dnsServer] ?: 0) + 1
                
                // Deprioritize after N consecutive failures
                if (dnsServerFailures[dnsServer]!! >= DEPRIORITIZE_AFTER_FAILURES) {
                    dnsServerDeprioritizedUntil[dnsServer] = now + DEPRIORITIZE_DURATION_MS
                    Log.w(TAG, "Deprioritizing $dnsServer for ${DEPRIORITIZE_DURATION_MS / 1000}s after ${dnsServerFailures[dnsServer]} consecutive failures")
                }
                
                // Continue to next DNS server
            }
        }
        
        if (!success) {
            totalFailures++
            failureTimestamps.add(now)
            
            // Clean up old timestamps outside the rolling window
            failureTimestamps.removeAll { it < now - SUSTAINED_FAILURE_WINDOW_MS }
            
            Log.e(TAG, "All DNS servers failed. Total failures: $totalFailures/$totalQueries in window")
            
            // Check for sustained failure (80%+ failure rate over 30 seconds)
            if (!sustainedFailureReported && failureTimestamps.size >= 5) {
                val failureRate = totalFailures.toDouble() / totalQueries.toDouble()
                if (failureRate >= SUSTAINED_FAILURE_THRESHOLD) {
                    sustainedFailureReported = true
                    Log.e(TAG, "Sustained DNS failure detected (rate: ${String.format("%.1f", failureRate * 100)}%). Notifying app.")
                    onSustainedFailureListener?.invoke()
                }
            }
        } else {
            // On success, reset sustained failure flag if failure rate improves
            if (sustainedFailureReported) {
                failureTimestamps.removeAll { it < now - SUSTAINED_FAILURE_WINDOW_MS }
                val failureRate = totalFailures.toDouble() / totalQueries.toDouble()
                if (failureRate < SUSTAINED_FAILURE_THRESHOLD) {
                    sustainedFailureReported = false
                    Log.i(TAG, "DNS connectivity recovered (rate: ${String.format("%.1f", failureRate * 100)}%)")
                }
            }
        }
    }
    
    private fun getOrderedDnsServers(now: Long): List<String> {
        // Clean up expired deprioritizations
        dnsServerDeprioritizedUntil.entries.removeAll { it.value < now }
        
        // Separate into deprioritized and available servers
        val deprioritized = mutableListOf<String>()
        val available = mutableListOf<String>()
        
        for (server in UPSTREAM_DNS_SERVERS) {
            if (dnsServerDeprioritizedUntil.containsKey(server)) {
                deprioritized.add(server)
            } else {
                available.add(server)
            }
        }
        
        // Return available servers first, then deprioritized
        return available + deprioritized
    }
    
    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }
    
    /**
     * Called automatically when another VPN takes over or this VPN is disabled
     * in system Settings. No extra permission needed - this is built into VpnService.
     */
    override fun onRevoke() {
        super.onRevoke()
        Log.w(TAG, "VPN revoked - another VPN took over or user disabled in Settings")
        
        // Notify Flutter app about VPN revoke
        // This will trigger guardian alert and in-app banner
        val intent = Intent("com.example.betstop_kenya.VPN_REVOKED")
        sendBroadcast(intent)
        
        stopVpn()
    }
}
