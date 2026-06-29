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
        id = "fal-ai/kling-video/v2.6/pro/text-to-video",
        name = "Kling 2.6 Pro",
        imageURL = "https://fal.ai/models/fal-ai/kling-video/v2.6/pro/text-to-video",
        runCount = 0
    ),
    AIModelOption(
        id = "fal-ai/kling-video/v2.5-turbo/pro/text-to-video",
        name = "Kling 2.5 Turbo Pro",
        imageURL = "https://fal.ai/models/fal-ai/kling-video/v2.5-turbo/pro/text-to-video",
        runCount = 0
    ),
    AIModelOption(
        id = "fal-ai/kling-video/v2.1/master/text-to-video",
        name = "Kling 2.1 Master",
        imageURL = "https://fal.ai/models/fal-ai/kling-video/v2.1/master/text-to-video",
        runCount = 0
    ),
    AIModelOption(
        id = "fal-ai/bytedance/seedance/v1/pro/text-to-video",
        name = "Seedance Pro",
        imageURL = "https://fal.ai/models/fal-ai/bytedance/seedance/v1/pro/text-to-video",
        runCount = 0
    ),
    AIModelOption(
        id = "fal-ai/bytedance/seedance/v1/lite/text-to-video",
        name = "Seedance Lite",
        imageURL = "https://fal.ai/models/fal-ai/bytedance/seedance/v1/lite/text-to-video",
        runCount = 0
    ),
    AIModelOption(
        id = "fal-ai/veo3/fast",
        name = "Veo 3 Fast",
        imageURL = "https://fal.ai/models/fal-ai/veo3/fast",
        runCount = 0
    )
)
