package com.example.betstop_kenya.dnsblock

import android.util.Log
import java.nio.ByteBuffer

/**
 * Parses DNS packets and extracts domain names from queries.
 * Also creates NXDOMAIN responses for blocked domains.
 */
class DnsPacketParser {
    
    companion object {
        private const val TAG = "DnsPacketParser"
        private const val DNS_HEADER_SIZE = 12
    }
    
    /**
     * Extract domain name from DNS query packet
     * Returns null if not a valid DNS query or parsing fails
     * 
     * Packet format: IP header + UDP header + DNS header + question section
     * TUN interfaces always deliver complete raw IP packets
     */
    fun extractDomainName(packet: ByteArray): String? {
        try {
            // Minimum size: IP header (20) + UDP header (8) + DNS header (12) = 40 bytes
            if (packet.size < 40) return null
            
            // Parse IP header to get IHL
            val versionAndIhl = packet[0].toInt() and 0xFF
            val version = (versionAndIhl shr 4) and 0x0F
            val ihl = (versionAndIhl and 0x0F) * 4 // Header length in bytes
            
            if (version != 4) return null // Only IPv4 supported
            if (packet.size < ihl + 8 + DNS_HEADER_SIZE) return null
            
            // Skip IP header
            var offset = ihl
            
            // Skip UDP header (8 bytes)
            offset += 8
            
            // Skip DNS header (12 bytes)
            offset += DNS_HEADER_SIZE
            
            // Parse domain name from question section
            val domainName = parseDomainName(packet, offset, mutableSetOf())
            
            return domainName
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting domain name: ${e.message}")
            return null
        }
    }
    
    /**
     * Parse domain name from DNS packet format per RFC 1035.
     * 
     * Domain names are encoded as label-length-value sequences:
     * Example: "www.example.com" -> [3]www[7]example[3]com[0]
     * 
     * Compression pointers (0xC0–0xFF) are followed to resolve compressed names.
     * Maximum 5 pointer jumps to prevent infinite loops.
     * 
     * @param packet Full packet bytes
     * @param offset Starting offset in packet (after DNS header)
     * @param visitedOffsets Set of visited pointer offsets to detect loops
     * @return Domain name string or null if parsing fails
     */
    private fun parseDomainName(packet: ByteArray, offset: Int, visitedOffsets: MutableSet<Int>): String? {
        val labels = mutableListOf<String>()
        var currentOffset = offset
        var jumps = 0
        val maxJumps = 5
        
        while (true) {
            // Check bounds
            if (currentOffset >= packet.size) return null
            
            val labelLength = packet[currentOffset].toInt() and 0xFF
            
            // End of domain name
            if (labelLength == 0) {
                break
            }
            
            // Check for compression pointer (top 2 bits set = 0xC0)
            if ((labelLength and 0xC0) == 0xC0) {
                // Need at least 2 bytes for pointer (length byte + offset byte)
                if (currentOffset + 1 >= packet.size) return null
                
                // Extract pointer offset (lower 14 bits)
                val pointerOffset = ((labelLength and 0x3F) shl 8) or (packet[currentOffset + 1].toInt() and 0xFF)
                
                // Prevent infinite loops
                if (jumps >= maxJumps) {
                    Log.w(TAG, "Too many compression pointer jumps ($jumps)")
                    return null
                }
                
                // Detect circular references
                if (visitedOffsets.contains(pointerOffset)) {
                    Log.w(TAG, "Circular compression pointer detected at offset $pointerOffset")
                    return null
                }
                
                visitedOffsets.add(pointerOffset)
                currentOffset = pointerOffset
                jumps++
                continue
            }
            
            // Regular label
            if (currentOffset + 1 + labelLength > packet.size) return null
            
            val labelBytes = packet.copyOfRange(currentOffset + 1, currentOffset + 1 + labelLength)
            
            // Validate label is printable ASCII
            for (byte in labelBytes) {
                val c = byte.toInt() and 0xFF
                if (c < 33 || c > 126) {
                    // Non-printable character
                    return null
                }
            }
            
            labels.add(String(labelBytes, Charsets.US_ASCII))
            currentOffset += 1 + labelLength
        }
        
        return if (labels.isNotEmpty()) {
            labels.joinToString(".")
        } else {
            null
        }
    }
    
    /**
     * Create NXDOMAIN (Name Error) response for a blocked domain
     * NXDOMAIN has RCODE = 3 (Name Error)
     */
    fun createNxDomainResponse(query: ByteArray): ByteArray? {
        try {
            val response = query.copyOf()
            val buffer = ByteBuffer.wrap(response)
            
            // Set RCODE to 3 (NXDOMAIN) in the DNS header
            // RCODE is in the lower 4 bits of byte 3
            val flags = buffer.getShort(2).toInt()
            val newFlags = (flags and 0xFFF0) or 0x0003  // Set RCODE to 3
            buffer.putShort(2, newFlags.toShort())
            
            // Set response bit (QR = 1)
            val qrFlags = buffer.getShort(2).toInt()
            val newQrFlags = qrFlags or 0x8000  // Set QR bit
            buffer.putShort(2, newQrFlags.toShort())
            
            // Set answer count to 0 (no answers for NXDOMAIN)
            buffer.putShort(6, 0)
            
            return response
        } catch (e: Exception) {
            Log.e(TAG, "Error creating NXDOMAIN response: ${e.message}")
            return null
        }
    }
}
