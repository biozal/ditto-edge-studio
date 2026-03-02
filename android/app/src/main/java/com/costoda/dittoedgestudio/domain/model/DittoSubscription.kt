package com.costoda.dittoedgestudio.domain.model

data class DittoSubscription(
    val id: Long = 0,
    val databaseId: String = "",
    val name: String = "",
    val query: String = ""
)
