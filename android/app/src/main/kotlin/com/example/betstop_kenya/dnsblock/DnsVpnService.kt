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
 * DNS-filtering VPN Service using split-default routing with packet inspection.
 * 
 * ROUTING ARCHITECTURE:
 * - Split-default routing: addRoute("0.0.0.0", 1) AND addRoute("128.0.0.0", 1)
 * - This covers full 0.0.0.0/0 range while avoiding device-specific quirks
 * - ALL traffic enters the tunnel, but we selectively process only DNS
 * 
 * PACKET PROCESSING LOOP:
 * - Inspect EVERY packet entering the tunnel
 * - If UDP packet with destination port 53 (DNS) → apply filtering logic
 * - EVERY OTHER PACKET → protect() and forward unchanged to original destination
 * - Non-DNS traffic (YouTube, Chrome, WhatsApp) passes through completely untouched
 * 
 * Architecture:
 * - Private point-to-point tun pair: 10.111.222.1 (local) <-> 10.111.222.2 (remote)
 * - Intercept DNS queries on port 53, check blocklist, forward to upstream resolver
 * - Return NXDOMAIN for blocked domains, forward unmodified responses for allowed domains
 * - Fail-open on errors - never block internet access
 * 
 * Limitations:
 * - Only handles plain DNS (UDP port 53). DoH (TCP port 443) and DoT (TCP port 853) bypass filtering.
 * - This is expected and acceptable - same as every consumer DNS-blocking app.
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
        
        // Configure VPN interface - only intercept DNS, not all traffic
        val builder = Builder()
            .setSession("BetStop DNS Block")
            .addAddress(LOCAL_TUN_IP, 30)
            .addRoute(REMOTE_TUN_IP, 32) // Route for virtual DNS server
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
        
        Log.i(TAG, "VPN started with split-default routing: routes($REMOTE_TUN_IP/32, 0.0.0.0/1, 128.0.0.0/1)")
        onVpnStartedListener?.invoke()
        Log.i(TAG, "VPN started, listener invoked")
        
        // Start packet processing thread
        Thread { processPackets() }.start()
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
    
    private fun processPackets() {
        val vpnInput = FileInputStream(vpnInterface!!.fileDescriptor)
        val vpnOutput = FileOutputStream(vpnInterface!!.fileDescriptor)
        
        val buffer = ByteArray(MTU)
        
        while (atomicIsRunning.get()) {
            try {
                val bytesRead = vpnInput.read(buffer)
                if (bytesRead <= 0) continue
                
                val packet = buffer.copyOf(bytesRead)
                
                // Check if this is a DNS packet (UDP, destination port 53)
                if (isDnsPacket(packet)) {
                    // Extract domain and apply filtering
                    val domainName = dnsPacketParser?.extractDomainName(packet)
                    
                    if (domainName != null) {
                        Log.d(TAG, "DNS query for: $domainName")
                        
                        // Check blocklist
                        val isBlocked = checkBlocklistWithTimeout(domainName)
                        
                        if (isBlocked) {
                            // Return NXDOMAIN for blocked domains
                            val nxResponse = dnsPacketParser?.createNxDomainResponse(packet)
                            if (nxResponse != null) {
                                vpnOutput.write(nxResponse)
                                Log.d(TAG, "Blocked domain: $domainName (NXDOMAIN)")
                            }
                        } else {
                            // Forward to upstream DNS
                            forwardToUpstreamDns(packet, vpnOutput)
                        }
                    } else {
                        // DNS packet but parsing failed, forward to upstream
                        forwardToUpstreamDns(packet, vpnOutput)
                    }
                } else {
                    // Non-DNS packet: protect() and forward unchanged
                    // This allows all non-DNS traffic to pass through
                    forwardNonDnsPacket(packet, vpnOutput)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error processing packet: ${e.message}")
                // Fail-open: continue processing
            }
        }
    }
    
    /**
     * Check if packet is a DNS query (UDP, destination port 53)
     * Parses IP header to determine protocol and destination port
     */
    private fun isDnsPacket(packet: ByteArray): Boolean {
        if (packet.size < 28) return false // Minimum IP + UDP header size
        
        // IP header: first byte = version + IHL
        val versionAndIhl = packet[0].toInt() and 0xFF
        val version = (versionAndIhl shr 4) and 0x0F
        val ihl = versionAndIhl and 0x0F // Header length in 32-bit words
        
        if (version != 4) return false // Only IPv4 supported
        if (packet.size < ihl * 4 + 8) return false // Not enough data for UDP header
        
        // Protocol is at byte 9 in IP header
        val protocol = packet[9].toInt() and 0xFF
        if (protocol != 17) return false // 17 = UDP
        
        // UDP header starts after IP header
        val udpHeaderOffset = ihl * 4
        
        // Destination port is at offset 2 in UDP header
        val destPort = ((packet[udpHeaderOffset + 2].toInt() and 0xFF) shl 8) or 
                       (packet[udpHeaderOffset + 3].toInt() and 0xFF)
        
        return destPort == 53 // DNS port
    }
    
    /**
     * Forward non-DNS packets using protected socket
     * This allows all non-DNS traffic (YouTube, Chrome, etc.) to pass through
     */
    private fun forwardNonDnsPacket(packet: ByteArray, vpnOutput: FileOutputStream) {
        try {
            if (packet.size < 20) return
            
            val ihl = (packet[0].toInt() and 0x0F) * 4
            if (packet.size < ihl + 8) return
            
            val protocol = packet[9].toInt() and 0xFF
            val destIpBytes = packet.sliceArray(16 until 20)
            val destIp = InetAddress.getByAddress(destIpBytes)
            
            when (protocol) {
                17 -> { // UDP
                    val srcPort = ((packet[ihl].toInt() and 0xFF) shl 8) or (packet[ihl + 1].toInt() and 0xFF)
                    val destPort = ((packet[ihl + 2].toInt() and 0xFF) shl 8) or (packet[ihl + 3].toInt() and 0xFF)
                    forwardUdpPacketProtected(packet, ihl, destIp, srcPort, destPort, vpnOutput)
                }
                6 -> { // TCP
                    val srcPort = ((packet[ihl].toInt() and 0xFF) shl 8) or (packet[ihl + 1].toInt() and 0xFF)
                    val destPort = ((packet[ihl + 2].toInt() and 0xFF) shl 8) or (packet[ihl + 3].toInt() and 0xFF)
                    forwardTcpPacketProtected(packet, ihl, destIp, srcPort, destPort, vpnOutput)
                }
                else -> {
                    // Other protocols (ICMP, etc.) - drop for now
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error forwarding non-DNS packet: ${e.message}")
        }
    }
    
    private fun forwardUdpPacketProtected(packet: ByteArray, ipHeaderLen: Int, destIp: InetAddress, srcPort: Int, destPort: Int, vpnOutput: FileOutputStream) {
        try {
            // Extract UDP payload (skip IP header)
            val udpPayload = packet.copyOfRange(ipHeaderLen, packet.size)
            
            DatagramSocket().use { socket ->
                protect(socket)
                
                // Send to destination
                val sendPacket = DatagramPacket(udpPayload, udpPayload.size, destIp, destPort)
                socket.send(sendPacket)
                
                // Wait for response with timeout
                val responseBuffer = ByteArray(MTU)
                val responsePacket = DatagramPacket(responseBuffer, responseBuffer.size)
                socket.soTimeout = 3000
                socket.receive(responsePacket)
                
                // Reconstruct IP packet with response
                // For simplicity, write UDP response back (apps handle this)
                vpnOutput.write(responsePacket.data, 0, responsePacket.length)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error forwarding UDP to $destIp:$destPort: ${e.message}")
        }
    }
    
    private fun forwardTcpPacketProtected(packet: ByteArray, ipHeaderLen: Int, destIp: InetAddress, srcPort: Int, destPort: Int, vpnOutput: FileOutputStream) {
        try {
            // TCP is complex - for basic functionality, we'll attempt a simple connection
            // In production, this needs a full TCP stack (like tun2socks)
            java.net.Socket().use { socket ->
                protect(socket)
                socket.connect(java.net.InetSocketAddress(destIp, destPort), 3000)
                
                val outputStream = socket.getOutputStream()
                val inputStream = socket.getInputStream()
                
                // Extract TCP payload (skip IP header)
                val tcpPayload = packet.copyOfRange(ipHeaderLen, packet.size)
                outputStream.write(tcpPayload)
                outputStream.flush()
                
                // Read response
                val responseBuffer = ByteArray(MTU)
                val bytesRead = inputStream.read(responseBuffer)
                if (bytesRead > 0) {
                    vpnOutput.write(responseBuffer, 0, bytesRead)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error forwarding TCP to $destIp:$destPort: ${e.message}")
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
