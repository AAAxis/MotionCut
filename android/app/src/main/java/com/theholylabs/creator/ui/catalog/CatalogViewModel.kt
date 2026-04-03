package com.theholylabs.creator.ui.catalog

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.net.URL

data class CatalogItem(
    val id: String,
    val prompt: String,
    val mode: String,
    val model: String,
    val videoUrl: String,
    val thumbnailUrl: String?,
    val createdAt: String,
)

@Serializable
private data class CatalogResponse(
    val items: List<CatalogRowDTO>,
    val total: Int,
)

@Serializable
private data class CatalogRowDTO(
    val id: String,
    val prompt: String,
    val mode: String,
    val model: String,
    val videoUrl: String,
    val thumbnailUrl: String? = null,
    val createdAt: String,
)

class CatalogViewModel : ViewModel() {

    private val _generations = MutableStateFlow<List<CatalogItem>>(emptyList())
    val generations = _generations.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading = _isLoading.asStateFlow()

    private val _hasMore = MutableStateFlow(true)
    val hasMore = _hasMore.asStateFlow()

    private val _playingId = MutableStateFlow<String?>(null)
    val playingId = _playingId.asStateFlow()

    private var currentPage = 1
    private val limit = 24

    private val catalogURL = "https://www.creatorai.art/api/catalog"
    private val json = Json { ignoreUnknownKeys = true }

    fun loadGenerations() {
        if (_isLoading.value) return
        viewModelScope.launch {
            _isLoading.value = true
            currentPage = 1
            val items = fetchCatalog(1)
            _generations.value = items
            _hasMore.value = items.size >= limit
            _isLoading.value = false
        }
    }

    fun loadMore() {
        if (_isLoading.value || !_hasMore.value) return
        viewModelScope.launch {
            _isLoading.value = true
            currentPage++
            val items = fetchCatalog(currentPage)
            _generations.value = _generations.value + items
            _hasMore.value = items.size >= limit
            _isLoading.value = false
        }
    }

    fun togglePlay(id: String) {
        _playingId.value = if (_playingId.value == id) null else id
    }

    private suspend fun fetchCatalog(page: Int): List<CatalogItem> = withContext(Dispatchers.IO) {
        try {
            val url = URL("$catalogURL?page=$page&limit=$limit")
            val text = url.readText()
            val response = json.decodeFromString<CatalogResponse>(text)

            response.items.map { row ->
                CatalogItem(
                    id = row.id,
                    prompt = row.prompt,
                    mode = row.mode,
                    model = row.model,
                    videoUrl = row.videoUrl,
                    thumbnailUrl = row.thumbnailUrl,
                    createdAt = row.createdAt,
                )
            }
        } catch (e: Exception) {
            Log.e("CatalogViewModel", "Fetch failed", e)
            emptyList()
        }
    }
}
