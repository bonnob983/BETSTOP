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
     */
    fun extractDomainName(packet: ByteArray): String? {
        try {
            if (packet.size < DNS_HEADER_SIZE) return null
            
            val buffer = ByteBuffer.wrap(packet)
            
            // Skip DNS header (12 bytes)
            buffer.position(DNS_HEADER_SIZE)
            
            // Parse question section
            val domainName = parseDomainName(buffer)
            
            return domainName
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting domain name: ${e.message}")
            return null
        }
    }
    
    /**
     * Parse domain name from DNS packet format
     * Domain names are encoded as label-length-value sequences
     * Example: "www.example.com" -> [3]www[7]example[3]com[0]
     */
    private fun parseDomainName(buffer: ByteBuffer): String? {
        val labels = mutableListOf<String>()
        
        while (true) {
            if (buffer.remaining() < 1) return null
            
            val labelLength = buffer.get().toInt() and 0xFF
            
            if (labelLength == 0) {
                // End of domain name
                break
            }
            
            // Check for compression pointer (top 2 bits set)
            if ((labelLength and 0xC0) == 0xC0) {
                // Compression pointer - not supported in this simple implementation
                // Skip the pointer byte and the next byte
                if (buffer.remaining() < 1) return null
                buffer.get()
                break
            }
            
            if (buffer.remaining() < labelLength) return null
            
            val labelBytes = ByteArray(labelLength)
            buffer.get(labelBytes)
            labels.add(String(labelBytes, Charsets.US_ASCII))
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
