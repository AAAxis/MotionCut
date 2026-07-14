package com.theholylabs.creator.viewmodels

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.theholylabs.creator.models.Generation
import com.theholylabs.creator.services.GenerationService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.File

class LibraryViewModel(application: Application) : AndroidViewModel(application) {
    private val _generations = MutableStateFlow<List<Generation>>(emptyList())
    val generations: StateFlow<List<Generation>> = _generations.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    fun loadGenerations(userId: String? = null) {
        viewModelScope.launch {
            _isLoading.value = true
            val local = GenerationService.loadLocalGenerations(getApplication())
                .filter { it.hasLocalLibraryMedia }
            GenerationService.saveGenerationsLocal(getApplication(), local)
            _generations.value = local.sortedByDescending { it.createdAt }
            _isLoading.value = false
        }
    }

    fun deleteGeneration(id: String, userId: String? = null) {
        viewModelScope.launch {
            val existing = GenerationService.loadLocalGenerations(getApplication()).toMutableList()
            val gen = existing.find { it.id == id }

            // Delete local video files
            gen?.videoUri?.let { uri ->
                try { File(uri).delete() } catch (_: Exception) {}
                // Also delete associated clip files
                try {
                    File(uri).parentFile?.listFiles()?.filter {
                        it.name.startsWith("${id}_clip_") || it.name.startsWith("${id}_voiceover")
                    }?.forEach { it.delete() }
                } catch (_: Exception) {}
            }
            gen?.resultVideoUrl?.let { url ->
                if (url.startsWith("/")) {
                    try { File(url).delete() } catch (_: Exception) {}
                }
            }

            existing.removeAll { it.id == id }
            GenerationService.saveGenerationsLocal(getApplication(), existing)
            _generations.value = existing.sortedByDescending { it.createdAt }
        }
    }
}
