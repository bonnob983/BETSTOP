package com.example.betstop_kenya.dnsblock

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Manages the DNS blocklist for gambling domains.
 * 
 * Blocklist source: Supabase blocked_domains table
 * Filter: is_active=true only
 * Matching: Exact domain + subdomains only (no partial/keyword matching)
 */
class BlocklistManager(private val context: Context) {
    
    companion object {
        private const val TAG = "BlocklistManager"
        private const val BLOCKLIST_FILE = "dns_blocklist.json"
        private const val SUPABASE_URL = "https://betstop-production-033f.up.railway.app"
        private const val BLOCKLIST_ENDPOINT = "/api/blocklist/domains"
    }
    
    private val blockedDomains = mutableSetOf<String>()
    private var loaded = false
    
    /**
     * Load blocklist from local cache or fetch from Supabase
     * Returns true if successful, false otherwise
     */
    fun loadBlocklist(): Boolean {
        try {
            // Try to load from local cache first
            val cached = loadFromCache()
            if (cached.isNotEmpty()) {
                blockedDomains.clear()
                blockedDomains.addAll(cached)
                loaded = true
                Log.i(TAG, "Loaded ${blockedDomains.size} domains from cache")
                return true
            }
            
            Log.e(TAG, "Failed to load blocklist from any source")
            return false
        } catch (e: Exception) {
            Log.e(TAG, "Error loading blocklist: ${e.message}")
            return false
        }
    }
    
    /**
     * Check if a domain is blocked
     * Matches exact domain + subdomains only
     * Example: "betika.com" blocks "betika.com" and "www.betika.com"
     * Does NOT block "notbetika.com" or "betika.com.fake"
     */
    fun isBlocked(domain: String): Boolean {
        if (!loaded) return false
        
        val normalizedDomain = domain.lowercase().trim()
        
        // Check exact match
        if (blockedDomains.contains(normalizedDomain)) {
            return true
        }
        
        // Check subdomain match
        // If "betika.com" is blocked, then "www.betika.com" should also be blocked
        // We extract the root domain and check if it's in the blocklist
        val parts = normalizedDomain.split(".")
        if (parts.size >= 2) {
            // Build possible parent domains
            // For "sub.domain.com", check "domain.com" and "sub.domain.com"
            for (i in 1 until parts.size) {
                val parentDomain = parts.subList(i, parts.size).joinToString(".")
                if (blockedDomains.contains(parentDomain)) {
                    return true
                }
            }
        }
        
        return false
    }
    
    private fun loadFromCache(): Set<String> {
        try {
            val file = File(context.filesDir, BLOCKLIST_FILE)
            if (!file.exists()) return emptySet()
            
            val content = file.readText()
            val json = JSONObject(content)
            val domainsArray = json.optJSONArray("domains") ?: return emptySet()
            
            val domains = mutableSetOf<String>()
            for (i in 0 until domainsArray.length()) {
                domains.add(domainsArray.getString(i).lowercase())
            }
            
            return domains
        } catch (e: Exception) {
            Log.e(TAG, "Error loading from cache: ${e.message}")
            return emptySet()
        }
    }
    
    private suspend fun fetchFromSupabase(): Set<String> = withContext(Dispatchers.IO) {
        try {
            // Note: This is a placeholder. In production, you'd use proper HTTP client
            // with authentication headers from the Flutter app
            // For now, we'll use a simple HTTP request
            
            val url = "$SUPABASE_URL$BLOCKLIST_ENDPOINT"
            Log.d(TAG, "Fetching blocklist from: $url")
            
            // TODO: Implement actual HTTP fetch with proper authentication
            // For now, return empty set - this will be implemented via Flutter service
            Log.w(TAG, "Supabase fetch not yet implemented - using Flutter service instead")
            return@withContext emptySet()
        } catch (e: Exception) {
            Log.e(TAG, "Error fetching from Supabase: ${e.message}")
            return@withContext emptySet()
        }
    }
    
    /**
     * Update blocklist from Flutter (called via MethodChannel)
     * This allows the Flutter app to fetch from Supabase and pass the blocklist to native code
     */
    fun updateBlocklist(domains: List<String>) {
        blockedDomains.clear()
        blockedDomains.addAll(domains.map { it.lowercase() })
        loaded = true
        Log.i(TAG, "Updated blocklist with ${blockedDomains.size} domains from Flutter")
        
        // Save to cache
        saveToCache()
    }
    
    private fun saveToCache() {
        try {
            val file = File(context.filesDir, BLOCKLIST_FILE)
            val json = JSONObject()
            val domainsArray = JSONArray(blockedDomains.toList())
            json.put("domains", domainsArray)
            json.put("updated_at", System.currentTimeMillis())
            file.writeText(json.toString())
            Log.d(TAG, "Saved blocklist to cache")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving to cache: ${e.message}")
        }
    }
}
