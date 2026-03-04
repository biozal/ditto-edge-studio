package com.costoda.dittoedgestudio.util

import com.costoda.dittoedgestudio.domain.model.DittoDatabase

data class QrImportResult(
    val database: DittoDatabase,
    val favorites: List<String>,
)
