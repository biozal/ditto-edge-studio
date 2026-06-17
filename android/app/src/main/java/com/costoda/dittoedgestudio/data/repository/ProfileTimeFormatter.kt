package com.costoda.dittoedgestudio.data.repository

import java.util.Locale

/**
 * Three-tier auto-scale formatter for nanosecond durations.
 *
 * | Raw value           | Display          |
 * |---------------------|------------------|
 * | < 1_000 ns          | `<n> ns`         |
 * | 1_000 – 999_999 ns  | `<v>.<dd> µs`    |
 * | ≥ 1_000_000 ns      | `<v>.<dd> ms`    |
 *
 * Matches SwiftUI's `ProfileTimeFormatter.swift`. See `docs/PROFILE.md` § Display tiers.
 */
object ProfileTimeFormatter {
    fun format(ns: Long): String = when {
        ns < 1_000L -> "$ns ns"
        ns < 1_000_000L -> {
            val us = ns / 1_000.0
            String.format(Locale.US, "%.2f µs", Math.floor(us * 100) / 100)
        }
        else -> {
            val ms = ns / 1_000_000.0
            String.format(Locale.US, "%.2f ms", Math.floor(ms * 100) / 100)
        }
    }
}
