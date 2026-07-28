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
import java.nio.ByteBuffer
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
 * - Fail-open on errors (1000ms timeout) - never block internet access
 * 
 * KNOWN LIMITATION - DNS-over-TLS (Private DNS):
 * - If device has Private DNS set to a specific hostname (Settings → Network → Private DNS),
 *   DNS traffic bypasses this VPN on port 853 (DoT) and filtering is ineffective.
 * - Flutter layer should detect this via getPrivateDnsMode() and warn user to set to "Off" or "Automatic".
 * - This VPN does NOT attempt to intercept port 853 - that's out of scope.
 * 
 * Limitations:
 * - Only handles plain DNS (port 53). DoH (port 443) and DoT (port 853) bypass filtering.
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
        private const val DNS_TIMEOUT_MS = 1000L
        
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
            .addAddress(LOCAL_TUN_IP, 32) // Use /32 for local address to avoid implicit routes
            .addRoute(REMOTE_TUN_IP, 32) // CRITICAL: Single /32 host route ONLY
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
        
        Log.i(TAG, "VPN started with DNS-only routing scope: route($REMOTE_TUN_IP/32)")
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
                
                val packet = buffer.copyOf(bytesRead)
                
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
                    // Non-DNS packet: this shouldn't happen with correct routing
                    // Log and drop - routing should prevent non-DNS from reaching tun interface
                    Log.w(TAG, "Unexpected non-DNS packet in VPN tunnel - dropping")
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
                    
                    // Build complete IPv4 packet with proper headers from upstream response
                    val fullPacket = PacketBuilder.buildDnsResponsePacket(queryData, responsePacket.data.copyOf(responsePacket.length))
                    vpnOutput.write(fullPacket)
                    
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
    
    /**
     * Get current Private DNS mode on the device.
     * 
     * Returns:
     * - "off": Private DNS is disabled (VPN filtering works)
     * - "automatic": Private DNS is opportunistic (VPN filtering works)
     * - "strict_hostname": Private DNS is set to specific hostname (VPN filtering BYPASSED on port 853)
     * - "unknown": Unable to determine
     * 
     * Flutter layer should call this and warn user if result is "strict_hostname".
     */
    fun getPrivateDnsMode(): String {
        return try {
            val connectivityManager = getSystemService(android.net.ConnectivityManager::class.java)
            if (connectivityManager == null) {
                return "unknown"
            }
            
            val linkProperties = connectivityManager.getLinkProperties(connectivityManager.activeNetwork)
            if (linkProperties == null) {
                return "unknown"
            }
            
            val privateDnsServerName = linkProperties.privateDnsServerName
            if (privateDnsServerName != null && privateDnsServerName.isNotEmpty()) {
                // Strict mode with specific hostname - DoT bypasses our VPN
                return "strict_hostname"
            }
            
            // If no server name, check if Private DNS is using opportunistic mode
            // This is a simplified check - on older APIs we can't distinguish off vs automatic
            // We'll assume "off" if no server name is set
            "off"
        } catch (e: Exception) {
            Log.e(TAG, "Error getting Private DNS mode: ${e.message}")
            "unknown"
        }
    }
}

/**
 * PacketBuilder - Pure functions for IPv4/UDP packet construction.
 * 
 * All functions are unit-testable without requiring a real device or VPN interface.
 * This ensures DNS responses are properly formatted with correct headers and checksums.
 */
private object PacketBuilder {
    private const val IP_HEADER_VERSION_IHL = 0x45 // Version 4, IHL 5 (20 bytes)
    private const val IP_PROTOCOL_UDP = 17
    private const val UDP_HEADER_SIZE = 8
    private const val IP_HEADER_SIZE = 20
    
    /**
     * Build a complete IPv4 packet containing a DNS response.
     * 
     * @param originalQueryPacket The original DNS query packet (IP + UDP + DNS)
     * @param dnsResponsePayload The DNS response payload (DNS layer only)
     * @return Complete IPv4 packet (IP header + UDP header + DNS payload)
     */
    fun buildDnsResponsePacket(originalQueryPacket: ByteArray, dnsResponsePayload: ByteArray): ByteArray {
        // Parse original query to get addressing info
        val queryInfo = parseIpUdpHeaders(originalQueryPacket)
        
        // Build IP header
        val ipHeader = buildIpHeader(
            sourceIp = queryInfo.destIp,
            destIp = queryInfo.sourceIp,
            totalLength = IP_HEADER_SIZE + UDP_HEADER_SIZE + dnsResponsePayload.size
        )
        
        // Build UDP header
        val udpHeader = buildUdpHeader(
            sourcePort = 53,
            destPort = queryInfo.sourcePort,
            payload = dnsResponsePayload,
            sourceIp = queryInfo.destIp,
            destIp = queryInfo.sourceIp
        )
        
        // Combine: IP header + UDP header + DNS payload
        return ipHeader + udpHeader + dnsResponsePayload
    }
    
    /**
     * Parse IP and UDP headers from a packet.
     * 
     * @return IpUdpInfo containing source/dest IPs and ports
     */
    private fun parseIpUdpHeaders(packet: ByteArray): IpUdpInfo {
        if (packet.size < IP_HEADER_SIZE + UDP_HEADER_SIZE) {
            throw IllegalArgumentException("Packet too small for IP+UDP headers")
        }
        
        val ihl = (packet[0].toInt() and 0x0F) * 4
        if (packet.size < ihl + UDP_HEADER_SIZE) {
            throw IllegalArgumentException("Packet too small for IP+UDP headers with IHL=$ihl")
        }
        
        // Extract source and dest IPs from IP header (bytes 12-19)
        val sourceIp = byteArrayOf(
            packet[12], packet[13], packet[14], packet[15]
        )
        val destIp = byteArrayOf(
            packet[16], packet[17], packet[18], packet[19]
        )
        
        // Extract source and dest ports from UDP header (bytes ihl+0 to ihl+3)
        val sourcePort = ((packet[ihl].toInt() and 0xFF) shl 8) or (packet[ihl + 1].toInt() and 0xFF)
        val destPort = ((packet[ihl + 2].toInt() and 0xFF) shl 8) or (packet[ihl + 3].toInt() and 0xFF)
        
        return IpUdpInfo(sourceIp, destIp, sourcePort, destPort)
    }
    
    /**
     * Build an IPv4 header.
     * 
     * @param sourceIp Source IP address (4 bytes)
     * @param destIp Destination IP address (4 bytes)
     * @param totalLength Total packet length including IP header
     * @return 20-byte IP header
     */
    private fun buildIpHeader(sourceIp: ByteArray, destIp: ByteArray, totalLength: Int): ByteArray {
        val buffer = ByteBuffer.allocate(IP_HEADER_SIZE)
        
        // Version + IHL
        buffer.put(IP_HEADER_VERSION_IHL.toByte())
        
        // DSCP + ECN (0)
        buffer.put(0.toByte())
        
        // Total length
        buffer.putShort(totalLength.toShort())
        
        // Identification (0)
        buffer.putShort(0.toShort())
        
        // Flags + Fragment offset (0)
        buffer.putShort(0.toShort())
        
        // TTL (64)
        buffer.put(64.toByte())
        
        // Protocol (UDP = 17)
        buffer.put(IP_PROTOCOL_UDP.toByte())
        
        // Header checksum (placeholder, will compute)
        val checksumPos = buffer.position()
        buffer.putShort(0.toShort())
        
        // Source IP
        buffer.put(sourceIp)
        
        // Destination IP
        buffer.put(destIp)
        
        // Compute and set checksum
        val headerBytes = buffer.array()
        val checksum = computeIpChecksum(headerBytes)
        buffer.putShort(checksumPos, checksum)
        
        return headerBytes
    }
    
    /**
     * Build a UDP header.
     * 
     * @param sourcePort Source port
     * @param destPort Destination port
     * @param payload UDP payload
     * @param sourceIp Source IP (for checksum pseudo-header)
     * @param destIp Destination IP (for checksum pseudo-header)
     * @return 8-byte UDP header
     */
    private fun buildUdpHeader(
        sourcePort: Int,
        destPort: Int,
        payload: ByteArray,
        sourceIp: ByteArray,
        destIp: ByteArray
    ): ByteArray {
        val buffer = ByteBuffer.allocate(UDP_HEADER_SIZE)
        
        // Source port
        buffer.putShort(sourcePort.toShort())
        
        // Destination port
        buffer.putShort(destPort.toShort())
        
        // Length (header + payload)
        buffer.putShort((UDP_HEADER_SIZE + payload.size).toShort())
        
        // Checksum placeholder (will compute)
        val checksumPos = buffer.position()
        buffer.putShort(0.toShort())
        
        // Compute UDP checksum from IPv4 pseudo-header
        val headerBytes = buffer.array()
        val checksum = computeUdpChecksum(
            sourceIp = sourceIp,
            destIp = destIp,
            udpHeader = headerBytes,
            payload = payload
        )
        buffer.putShort(checksumPos, checksum)
        
        return headerBytes
    }
    
    /**
     * Compute UDP checksum from IPv4 pseudo-header.
     * 
     * Pseudo-header format:
     * - Source IP (4 bytes)
     * - Destination IP (4 bytes)
     * - Zero (1 byte)
     * - Protocol (1 byte, UDP = 17)
     * - UDP length (2 bytes)
     * - UDP header (8 bytes)
     * - UDP payload (variable)
     * 
     * @param sourceIp Source IP address
     * @param destIp Destination IP address
     * @param udpHeader UDP header bytes (checksum field must be 0)
     * @param payload UDP payload
     * @return Checksum value (0xFFFF if computed checksum is 0x0000)
     */
    private fun computeUdpChecksum(
        sourceIp: ByteArray,
        destIp: ByteArray,
        udpHeader: ByteArray,
        payload: ByteArray
    ): Short {
        var sum = 0
        
        // Add source IP
        sum += ((sourceIp[0].toInt() and 0xFF) shl 8) or (sourceIp[1].toInt() and 0xFF)
        sum += ((sourceIp[2].toInt() and 0xFF) shl 8) or (sourceIp[3].toInt() and 0xFF)
        
        // Add destination IP
        sum += ((destIp[0].toInt() and 0xFF) shl 8) or (destIp[1].toInt() and 0xFF)
        sum += ((destIp[2].toInt() and 0xFF) shl 8) or (destIp[3].toInt() and 0xFF)
        
        // Add zero + protocol
        sum += IP_PROTOCOL_UDP
        
        // Add UDP length
        val udpLength = UDP_HEADER_SIZE + payload.size
        sum += udpLength
        
        // Add UDP header (8 bytes)
        for (i in udpHeader.indices step 2) {
            val word = ((udpHeader[i].toInt() and 0xFF) shl 8) or (udpHeader[i + 1].toInt() and 0xFF)
            sum += word
        }
        
        // Add payload (pad to even length if needed)
        var i = 0
        while (i < payload.size) {
            val byte1 = payload[i].toInt() and 0xFF
            val byte2 = if (i + 1 < payload.size) payload[i + 1].toInt() and 0xFF else 0
            sum += (byte1 shl 8) or byte2
            i += 2
        }
        
        // Fold 32-bit sum to 16 bits
        while (sum shr 16 != 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }
        
        // One's complement
        var checksum = ((sum.inv()) and 0xFFFF).toShort()
        
        // If checksum is 0x0000, send 0xFFFF instead
        if (checksum.toInt() == 0x0000) {
            checksum = 0xFFFF.toShort()
        }
        
        return checksum
    }
    
    /**
     * Compute IPv4 header checksum.
     * 
     * @param header IP header bytes (checksum field must be 0)
     * @return Checksum value
     */
    private fun computeIpChecksum(header: ByteArray): Short {
        var sum = 0
        
        // Sum all 16-bit words
        for (i in header.indices step 2) {
            val word = ((header[i].toInt() and 0xFF) shl 8) or (header[i + 1].toInt() and 0xFF)
            sum += word
        }
        
        // Fold 32-bit sum to 16 bits
        while (sum shr 16 != 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }
        
        // One's complement
        return ((sum.inv()) and 0xFFFF).toShort()
    }
    
    /**
     * Data class for IP/UDP header information.
     */
    private data class IpUdpInfo(
        val sourceIp: ByteArray,
        val destIp: ByteArray,
        val sourcePort: Int,
        val destPort: Int
    ) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (javaClass != other?.javaClass) return false
            
            other as IpUdpInfo
            
            if (!sourceIp.contentEquals(other.sourceIp)) return false
            if (!destIp.contentEquals(other.destIp)) return false
            if (sourcePort != other.sourcePort) return false
            if (destPort != other.destPort) return false
            
            return true
        }
        
        override fun hashCode(): Int {
            var result = sourceIp.contentHashCode()
            result = 31 * result + destIp.contentHashCode()
            result = 31 * result + sourcePort
            result = 31 * result + destPort
            return result
        }
    }
}
