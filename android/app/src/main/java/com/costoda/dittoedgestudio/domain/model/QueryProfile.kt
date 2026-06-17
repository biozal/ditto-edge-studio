package com.costoda.dittoedgestudio.domain.model

data class QueryProfile(
    val id: String,
    val appId: String,
    val featureFlags: String,
    val queryType: String,
    val requestType: String,
    val resultCount: Int,
    val state: String,
    val text: String,
    val times: QueryProfileTimes,
    val plan: QueryProfileOperator,
    /** Wall-clock instant we parsed the profile on the client. */
    val capturedAtMs: Long,
)

data class QueryProfileTimes(
    val elapsedNs: Long,
    val parseNs: Long,
    val planNs: Long,
    val startISO: String,
)

data class QueryProfileOperator(
    /** Stable per-parse synthesised identifier (string UUID) — drives Compose `key()`s. */
    val id: String,
    val name: String,
    val stats: QueryProfileStats?,
    val children: List<QueryProfileOperator>,
    /** Operator-specific attributes preserved in insertion order. */
    val attributes: List<Pair<String, String>>,
) {
    /** Recursive sum of `execNs` across this subtree — used for the plan percentage badge. */
    val subtreeExecNs: Long
        get() = (stats?.execNs ?: 0L) + children.sumOf { it.subtreeExecNs }
}

data class QueryProfileStats(
    val documentsIn: Int?,
    val documentsOut: Int?,
    val execNs: Long?,
    val recvNs: Long?,
    val sendNs: Long?,
)
