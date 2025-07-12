package com.costoda.edh

interface Platform {
    val name: String
}

expect fun getPlatform(): Platform