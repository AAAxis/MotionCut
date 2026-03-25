package com.theholylabs.creator.services

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

object CaptionService {

    private const val CAPTION_API = "http://44.201.125.130:3001"

    suspend fun addCaptions(
        generationId: String,
        videoUri: String,
        takesJson: String?
    ): String? = withContext(Dispatchers.IO) {
        try {
            val url = URL("$CAPTION_API/api/generations/$generationId/add-captions")
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.doOutput = true

            val body = buildJsonObject {
                put("videoUri", videoUri)
                if (takesJson != null) put("takesJson", takesJson)
            }.toString()

            OutputStreamWriter(conn.outputStream).use { it.write(body) }

            val responseCode = conn.responseCode
            if (responseCode == 200) {
                val response = conn.inputStream.bufferedReader().readText()
                response
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }
    }
}
