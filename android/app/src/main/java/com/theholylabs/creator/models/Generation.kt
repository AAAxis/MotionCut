package com.theholylabs.creator.models

import kotlinx.serialization.Serializable

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
    val createdAt: String, // String for now to match JSON easily
    val userId: String? = null
)
