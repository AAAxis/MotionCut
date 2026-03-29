package com.theholylabs.creator.services

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.jsoup.Jsoup
import org.jsoup.nodes.Document

/**
 * Scrapes product/website URLs locally on-device using Jsoup.
 * Used by both Stock and AI ad modes to extract product info
 * for better script generation.
 */
object LocalScraperService {

    private const val TAG = "LocalScraperService"
    private const val TIMEOUT_MS = 10000

    data class ScrapedPage(
        val title: String?,
        val description: String?,
        val ogImage: String?,
        val domain: String?,
        val features: List<String>,
        val images: List<String>,
        val price: String?
    ) {
        /** Combine all scraped info into a prompt-friendly string */
        fun toPromptContext(): String {
            val parts = mutableListOf<String>()
            title?.let { parts.add("Product: $it") }
            description?.let { parts.add("Description: $it") }
            price?.let { parts.add("Price: $it") }
            if (features.isNotEmpty()) {
                parts.add("Features: ${features.joinToString(", ")}")
            }
            domain?.let { parts.add("Website: $it") }
            return parts.joinToString(". ")
        }
    }

    /**
     * Scrape a URL and extract product/page metadata.
     * Returns null if the URL can't be reached.
     */
    suspend fun scrape(url: String): ScrapedPage? = withContext(Dispatchers.IO) {
        try {
            val normalizedUrl = if (!url.startsWith("http")) "https://$url" else url
            val doc: Document = Jsoup.connect(normalizedUrl)
                .userAgent("Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36")
                .timeout(TIMEOUT_MS)
                .followRedirects(true)
                .get()

            val title = doc.selectFirst("meta[property=og:title]")?.attr("content")
                ?: doc.title()

            val description = doc.selectFirst("meta[property=og:description]")?.attr("content")
                ?: doc.selectFirst("meta[name=description]")?.attr("content")

            val ogImage = doc.selectFirst("meta[property=og:image]")?.attr("content")

            val domain = try {
                java.net.URI(normalizedUrl).host?.removePrefix("www.")
            } catch (_: Exception) { null }

            // Extract features from list items, headings, etc.
            val features = extractFeatures(doc)

            // Extract product images
            val images = doc.select("img[src]")
                .mapNotNull { it.absUrl("src").takeIf { url -> url.isNotEmpty() } }
                .filter { it.contains("product", true) || it.contains("hero", true) || it.contains("main", true) }
                .take(5)

            // Try to find price
            val price = extractPrice(doc)

            ScrapedPage(
                title = title?.take(200),
                description = description?.take(500),
                ogImage = ogImage,
                domain = domain,
                features = features,
                images = images,
                price = price
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to scrape $url: ${e.message}")
            null
        }
    }

    private fun extractFeatures(doc: Document): List<String> {
        val features = mutableListOf<String>()

        // Look for feature lists (common patterns)
        val listItems = doc.select("ul li, ol li")
            .map { it.text().trim() }
            .filter { it.length in 10..150 }
            .take(8)
        features.addAll(listItems)

        // If no list items, try headings
        if (features.isEmpty()) {
            val headings = doc.select("h2, h3")
                .map { it.text().trim() }
                .filter { it.length in 5..100 }
                .take(6)
            features.addAll(headings)
        }

        return features.distinct().take(8)
    }

    private fun extractPrice(doc: Document): String? {
        // Common price selectors
        val priceSelectors = listOf(
            "[class*=price]", "[id*=price]",
            "[class*=Price]", "[id*=Price]",
            "[data-price]", ".price", "#price"
        )

        for (selector in priceSelectors) {
            val element = doc.selectFirst(selector)
            if (element != null) {
                val text = element.text().trim()
                // Check if it looks like a price (contains currency symbol or number)
                if (text.matches(Regex(".*[\\$\\€\\£\\¥\\₪]\\s*\\d+.*")) ||
                    text.matches(Regex(".*\\d+[.,]\\d{2}.*"))) {
                    return text.take(50)
                }
            }
        }

        return null
    }
}
