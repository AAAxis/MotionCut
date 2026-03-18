package com.theholylabs.creator.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.theholylabs.creator.models.Generation
import com.theholylabs.creator.services.GenerationService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class LibraryViewModel : ViewModel() {
    private val _generations = MutableStateFlow<List<Generation>>(emptyList())
    val generations: StateFlow<List<Generation>> = _generations.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    fun loadGenerations(userId: String) {
        viewModelScope.launch {
            _isLoading.value = true
            _generations.value = GenerationService.fetchGenerations(userId)
            _isLoading.value = false
        }
    }

    fun deleteGeneration(id: String, userId: String) {
        viewModelScope.launch {
            if (GenerationService.deleteGeneration(id)) {
                loadGenerations(userId)
            }
        }
    }
}
