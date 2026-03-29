package com.theholylabs.creator.services

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale
import java.util.UUID
import kotlin.coroutines.resume

object LocalTTSService {

    private var tts: TextToSpeech? = null
    private var isReady = false

    private val languageMap = mapOf(
        "en" to Locale.US,
        "he" to Locale("he", "IL"),
        "ru" to Locale("ru", "RU"),
        "es" to Locale("es", "ES"),
        "de" to Locale.GERMANY,
        "fr" to Locale.FRANCE,
        "pt" to Locale("pt", "BR")
    )

    /**
     * Initialize TTS engine. Call once at app startup or before first use.
     */
    fun initialize(context: Context, onReady: () -> Unit = {}) {
        if (tts != null && isReady) {
            onReady()
            return
        }

        tts = TextToSpeech(context.applicationContext) { status ->
            isReady = status == TextToSpeech.SUCCESS
            if (isReady) {
                tts?.language = Locale.US
                tts?.setSpeechRate(1.0f)
                tts?.setPitch(1.0f)
                Log.d("LocalTTSService", "TTS initialized successfully")
                onReady()
            } else {
                Log.e("LocalTTSService", "TTS initialization failed: $status")
            }
        }
    }

    /**
     * Generate speech audio from text and save to a WAV file.
     * Returns the output file path, or null on failure.
     */
    suspend fun synthesizeToFile(
        text: String,
        language: String = "en",
        outputDir: File,
        filename: String = "tts_${UUID.randomUUID()}.wav"
    ): File? = withContext(Dispatchers.Main) {
        val engine = tts ?: return@withContext null
        if (!isReady) return@withContext null

        // Set language
        val locale = languageMap[language] ?: Locale.US
        val result = engine.setLanguage(locale)
        if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
            Log.w("LocalTTSService", "Language $language not available, falling back to English")
            engine.setLanguage(Locale.US)
        }

        outputDir.mkdirs()
        val outputFile = File(outputDir, filename)

        val utteranceId = UUID.randomUUID().toString()

        suspendCancellableCoroutine { continuation ->
            engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(id: String?) {}

                override fun onDone(id: String?) {
                    if (id == utteranceId) {
                        Log.d("LocalTTSService", "TTS synthesis complete: ${outputFile.name}")
                        continuation.resume(outputFile)
                    }
                }

                @Deprecated("Deprecated in Java")
                override fun onError(id: String?) {
                    if (id == utteranceId) {
                        Log.e("LocalTTSService", "TTS synthesis error for utterance $id")
                        continuation.resume(null)
                    }
                }

                override fun onError(id: String?, errorCode: Int) {
                    if (id == utteranceId) {
                        Log.e("LocalTTSService", "TTS synthesis error: code=$errorCode")
                        continuation.resume(null)
                    }
                }
            })

            val synthResult = engine.synthesizeToFile(text, null, outputFile, utteranceId)
            if (synthResult != TextToSpeech.SUCCESS) {
                Log.e("LocalTTSService", "synthesizeToFile returned error: $synthResult")
                continuation.resume(null)
            }
        }
    }

    /**
     * Synthesize voiceover for multiple scenes, returning a list of audio files.
     */
    suspend fun synthesizeScenes(
        scenes: List<SceneScript>,
        language: String = "en",
        outputDir: File
    ): List<File> {
        val results = mutableListOf<File>()
        for ((index, scene) in scenes.withIndex()) {
            val file = synthesizeToFile(
                text = scene.voiceoverText,
                language = language,
                outputDir = outputDir,
                filename = "voice_$index.wav"
            )
            if (file != null) results.add(file)
        }
        return results
    }

    fun shutdown() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        isReady = false
    }
}

data class SceneScript(
    val searchQuery: String,
    val subtitleText: String,
    val voiceoverText: String,
    val durationSeconds: Double = 3.0
)
