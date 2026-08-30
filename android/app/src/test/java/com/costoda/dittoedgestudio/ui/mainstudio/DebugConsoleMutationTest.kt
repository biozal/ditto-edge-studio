package com.costoda.dittoedgestudio.ui.mainstudio

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DebugConsoleMutationTest {

    @Test
    fun `mutating prefixes are detected case-insensitively with leading whitespace`() {
        assertTrue(isMutatingStatement("INSERT INTO t DOCUMENTS ({})"))
        assertTrue(isMutatingStatement("  evict from t"))
        assertTrue(isMutatingStatement("delete from t where _id = 'x'"))
        assertTrue(isMutatingStatement("ALTER SYSTEM SET x = 1"))
        assertTrue(isMutatingStatement("CREATE INDEX i ON t (a)"))
        assertTrue(isMutatingStatement("update t set a = 1"))
        assertTrue(isMutatingStatement("DROP INDEX t.i"))
    }

    @Test
    fun `select and friends do not trigger confirmation`() {
        assertFalse(isMutatingStatement("SELECT * FROM t"))
        assertFalse(isMutatingStatement("  select * from t"))
        assertFalse(isMutatingStatement("EXPLAIN SELECT * FROM t"))
        assertFalse(isMutatingStatement("ADVISE SELECT * FROM t"))
        assertFalse(isMutatingStatement(""))
    }
}
