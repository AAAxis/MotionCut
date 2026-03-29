package com.theholylabs.creator.models

import kotlinx.serialization.Serializable

@Serializable
data class AIModelOption(
    val id: String,
    val name: String,
    val imageURL: String,
    val runCount: Int
)

@Serializable
data class LanguageOption(
    val id: String,
    val label: String,
    val flag: String
)

val LANGUAGES = listOf(
    LanguageOption("en", "English", "US"),
    LanguageOption("he", "Hebrew", "IL"),
    LanguageOption("ru", "Russian", "RU"),
    LanguageOption("es", "Spanish", "ES"),
    LanguageOption("de", "German", "DE"),
    LanguageOption("fr", "French", "FR"),
    LanguageOption("pt", "Portuguese", "BR")
)

val PRESET_AI_MODELS = listOf(
    AIModelOption(
        id = "bytedance/seedance-1-lite",
        name = "Seedance Lite",
        imageURL = "https://tjzk.replicate.delivery/models_models_featured_image/961a33d5-e27a-4b15-8cdd-3e37d5375297/replicate-seedance-1-lite.webp",
        runCount = 2800000
    ),
    AIModelOption(
        id = "bytedance/seedance-1-pro",
        name = "Seedance Pro",
        imageURL = "https://tjzk.replicate.delivery/models_models_featured_image/b11bb650-a993-485b-b433-f1ba1c4cb90b/replicate-seedance-1-pro.webp",
        runCount = 1700000
    ),
    AIModelOption(
        id = "kwaivgi/kling-v2.1",
        name = "Kling v2.1",
        imageURL = "https://tjzk.replicate.delivery/models_models_featured_image/a7690882-d1d2-44fb-b487-f41bd367adcf/replicate-prediction-2epyczsz.webp",
        runCount = 3600000
    )
)
