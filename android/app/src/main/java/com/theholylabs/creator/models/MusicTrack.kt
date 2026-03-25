package com.theholylabs.creator.models

import kotlinx.serialization.Serializable

@Serializable
data class MusicTrack(
    val id: String,
    val name: String,
    val file: String,
    val title: String? = null
)
