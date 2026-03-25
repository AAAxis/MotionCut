package com.theholylabs.creator.models

import kotlinx.serialization.Serializable

@Serializable
data class Clip(
    val id: Int,
    val uri: String,
    val name: String = "",
    val mimeType: String = "video/mp4",
    val trimStart: Double = 0.0,
    val trimEnd: Double = 100.0,
    val beatDuration: Double? = null,
    val sourceDuration: Double? = null,
    val text: String? = null,
    val localUri: String? = null
)
