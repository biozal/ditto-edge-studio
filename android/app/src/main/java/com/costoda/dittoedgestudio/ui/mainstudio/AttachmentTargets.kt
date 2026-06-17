package com.costoda.dittoedgestudio.ui.mainstudio

/**
 * Shared helpers for resolving the attachment target (collection) from a DQL query string.
 *
 * Extracted from [com.costoda.dittoedgestudio.ui.mainstudio.inspector.QueryInspectorView] so
 * that [QueryResultsView] can share the same logic without duplication.
 */

/**
 * Best-effort: infer the target collection from the most recent query text.
 * Looks for `FROM <name>` (case-insensitive) and returns the matched identifier.
 * Returns null if the query doesn't have a recognisable FROM clause.
 *
 * v1 trade-off: works for `SELECT … FROM <c>` but not joins or aliased queries.
 * A future task should track the last-executed collection explicitly on workbench state.
 */
internal fun currentCollectionFromQuery(query: String): String? {
    val match = Regex("""\bFROM\s+([A-Za-z_][A-Za-z0-9_]*)""", RegexOption.IGNORE_CASE).find(query)
    return match?.groupValues?.get(1)
}
