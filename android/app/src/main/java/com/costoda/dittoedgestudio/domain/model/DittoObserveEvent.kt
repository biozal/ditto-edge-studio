package com.costoda.dittoedgestudio.domain.model

import java.util.UUID

data class DittoObserveEvent(
    val id: String = UUID.randomUUID().toString(),
    val observeId: String,
    val data: List<String> = emptyList(),
    val insertIndexes: List<Int> = emptyList(),
    val updatedIndexes: List<Int> = emptyList(),
    val deletedIndexes: List<Int> = emptyList(),
    val movedIndexes: List<Pair<Int, Int>> = emptyList(),
    val eventTime: String = "",
) {
    fun getInsertedData(): List<String> = insertIndexes.mapNotNull { data.getOrNull(it) }
    fun getUpdatedData(): List<String> = updatedIndexes.mapNotNull { data.getOrNull(it) }
}

enum class EventFilterMode { ALL, INSERTED, UPDATED }
