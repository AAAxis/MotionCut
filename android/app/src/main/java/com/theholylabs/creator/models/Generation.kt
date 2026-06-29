package com.theholylabs.creator.models

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject

@Serializable
enum class GenerationStatus {
    @kotlinx.serialization.SerialName("processing") PROCESSING,
    @kotlinx.serialization.SerialName("completed") COMPLETED,
    @kotlinx.serialization.SerialName("failed") FAILED,
    @kotlinx.serialization.SerialName("saved") SAVED
}

@Serializable
data class Generation(
    val id: String,
    val videoName: String,
    val videoUri: String? = null,
    val resultVideoUrl: String? = null,
    val status: GenerationStatus,
    val createdAt: String,
    val userId: String? = null,
    val takesJson: String? = null,
    val musicPath: String? = null
) {
    val displayName: String
        get() {
            val clean = videoName.trim()
            if (clean.isNotEmpty() && clean !in setOf("Editor", "Video", "Imported Video")) return clean
            titleFromTakesJson()?.let { return it }
            return clean.ifEmpty { "Video" }
        }

    private fun titleFromTakesJson(): String? {
        val json = takesJson ?: return null
        val arr = runCatching { Json.parseToJsonElement(json).jsonArray }.getOrNull() ?: return null
        for (key in listOf("prompt", "projectTitle", "text", "name")) {
            val value = arr.asSequence()
                .mapNotNull { it as? JsonObject }
                .mapNotNull { it[key] as? JsonPrimitive }
                .map { it.content.trim() }
                .firstOrNull { it.isNotEmpty() }
            if (value != null) return shortDisplayTitle(value)
        }
        return null
    }

    private fun shortDisplayTitle(value: String): String {
        val collapsed = value.split(Regex("\\s+")).joinToString(" ").trim()
        if (collapsed.length <= 42) return collapsed.ifEmpty { "Video" }
        val prefix = collapsed.take(42)
        return prefix.substringBeforeLast(" ", prefix)
    }
}
