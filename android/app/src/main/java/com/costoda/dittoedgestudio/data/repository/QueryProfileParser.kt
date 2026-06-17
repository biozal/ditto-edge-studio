package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.QueryProfile
import com.costoda.dittoedgestudio.domain.model.QueryProfileOperator
import com.costoda.dittoedgestudio.domain.model.QueryProfileStats
import com.costoda.dittoedgestudio.domain.model.QueryProfileTimes
import java.util.UUID

/**
 * Pure-Kotlin parser for the `~request_profile` envelope Ditto returns when a DQL
 * statement is prefixed with `PROFILE`.
 *
 * Mirrors SwiftUI's `QueryProfileParser` semantics — see `docs/PROFILE.md` for the
 * envelope shape and operator-tree contract. Returns `null` for items that don't look
 * like a profile envelope so the caller can keep them as normal result rows.
 */
object QueryProfileParser {

    const val envelopeKey: String = "~request_profile"

    fun parseItem(item: Map<String, Any?>): QueryProfile? {
        val envelope: Map<String, Any?> = when {
            item[envelopeKey] is Map<*, *> -> {
                @Suppress("UNCHECKED_CAST")
                item[envelopeKey] as Map<String, Any?>
            }
            item["_id"] != null && item["plan"] is Map<*, *> -> item  // bare
            else -> return null
        }
        val id = envelope["_id"] as? String ?: return null
        @Suppress("UNCHECKED_CAST")
        val planDict = envelope["plan"] as? Map<String, Any?> ?: return null
        val plan = parseOperator(planDict) ?: return null
        return QueryProfile(
            id = id,
            appId = (envelope["app_id"] as? String) ?: "",
            featureFlags = (envelope["featureFlags"] as? String) ?: "",
            queryType = (envelope["queryType"] as? String) ?: "",
            requestType = (envelope["requestType"] as? String) ?: "",
            resultCount = (envelope["resultCount"] as? Number)?.toInt() ?: 0,
            state = (envelope["state"] as? String) ?: "",
            text = (envelope["text"] as? String) ?: "",
            times = parseTimes(envelope["times"] as? Map<String, Any?>),
            plan = plan,
            capturedAtMs = System.currentTimeMillis(),
        )
    }

    /**
     * Walks the result list, removes the profile envelope item if present, and returns
     * (userDocuments, profile?). Preserves user-document order.
     */
    fun partition(items: List<Map<String, Any?>>): Pair<List<Map<String, Any?>>, QueryProfile?> {
        var profile: QueryProfile? = null
        val docs = mutableListOf<Map<String, Any?>>()
        for (item in items) {
            val parsed = parseItem(item)
            if (parsed != null && profile == null) {
                profile = parsed
            } else {
                docs += item
            }
        }
        return docs to profile
    }

    private fun parseTimes(dict: Map<String, Any?>?): QueryProfileTimes {
        if (dict == null) return QueryProfileTimes(0L, 0L, 0L, "")
        return QueryProfileTimes(
            elapsedNs = (dict["elapsed"] as? Number)?.toLong() ?: 0L,
            parseNs = (dict["parse"] as? Number)?.toLong() ?: 0L,
            planNs = (dict["plan"] as? Number)?.toLong() ?: 0L,
            startISO = (dict["start"] as? String) ?: "",
        )
    }

    private fun parseOperator(dict: Map<String, Any?>): QueryProfileOperator? {
        val name = dict["#operator"] as? String ?: return null
        @Suppress("UNCHECKED_CAST")
        val statsDict = dict["#stats"] as? Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val childList = (dict["children"] as? List<Map<String, Any?>>).orEmpty()
        val children = childList.mapNotNull { parseOperator(it) }
        val attributes = dict.entries
            .filter { it.key != "#operator" && it.key != "#stats" && it.key != "children" }
            .map { it.key to (it.value?.toString() ?: "") }
        return QueryProfileOperator(
            id = UUID.randomUUID().toString(),
            name = name,
            stats = parseStats(statsDict),
            children = children,
            attributes = attributes,
        )
    }

    private fun parseStats(dict: Map<String, Any?>?): QueryProfileStats? {
        if (dict == null) return null
        @Suppress("UNCHECKED_CAST")
        val phase = dict["phaseTimes"] as? Map<String, Any?>
        return QueryProfileStats(
            documentsIn = (dict["documentsIn"] as? Number)?.toInt(),
            documentsOut = (dict["documentsOut"] as? Number)?.toInt(),
            execNs = (phase?.get("exec") as? Number)?.toLong(),
            recvNs = (phase?.get("recv") as? Number)?.toLong(),
            sendNs = (phase?.get("send") as? Number)?.toLong(),
        )
    }
}
