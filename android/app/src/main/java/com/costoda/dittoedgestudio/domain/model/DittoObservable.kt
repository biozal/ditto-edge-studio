package com.costoda.dittoedgestudio.domain.model

data class DittoObservable(
    val id: Long = 0,
    val databaseId: String = "",
    val name: String = "",
    val query: String = "",
    val isActive: Boolean = false,
    val lastUpdated: Long? = null
)
