package com.costoda.dittoedgestudio.domain.model

data class DittoQueryHistory(
    val id: Long = 0,
    val databaseId: String = "",
    val query: String = "",
    val createdDate: Long = System.currentTimeMillis()
)
