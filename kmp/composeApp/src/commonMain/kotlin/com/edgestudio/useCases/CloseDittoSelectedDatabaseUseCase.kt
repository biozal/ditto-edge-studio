package com.edgestudio.useCases

import com.edgestudio.data.DittoManager

class CloseDittoSelectedDatabaseUseCase(
    private val dittoManager: DittoManager
) {
    operator fun invoke()  = dittoManager.closeSelectedDatabase()
}