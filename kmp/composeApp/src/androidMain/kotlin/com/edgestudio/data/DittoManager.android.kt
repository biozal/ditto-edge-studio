package com.edgestudio.data

import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoConfig
import com.ditto.kotlin.DittoFactory
import com.edgestudio.App

actual fun createDitto(config: DittoConfig): Ditto =
    DittoFactory.create(
        context = App.instance,
        config = config,
    )
