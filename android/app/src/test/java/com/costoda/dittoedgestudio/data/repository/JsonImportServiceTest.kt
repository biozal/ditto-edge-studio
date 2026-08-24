package com.costoda.dittoedgestudio.data.repository

import io.mockk.mockk
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/**
 * Validation tests for [JsonImportService]: the Ditto-dependent importData path
 * needs a live instance (covered by integration/manual testing), but validate()
 * is pure and gets full coverage.
 */
class JsonImportServiceTest {

    private val service = JsonImportService(dittoManager = mockk(relaxed = true))

    @Test
    fun `valid array of documents passes`() {
        val docs = service.validate("""[{"_id":"a","name":"x"},{"_id":2}]""")
        assertEquals(2, docs.size)
    }

    @Test
    fun `non-array json is rejected with the parity message`() {
        val e = assertThrows(JsonImportService.ImportException::class.java) {
            service.validate("""{"_id":"a"}""")
        }
        assertEquals("File must contain an array of JSON objects", e.message)
    }

    @Test
    fun `invalid json is rejected with the same message`() {
        val e = assertThrows(JsonImportService.ImportException::class.java) {
            service.validate("not json {")
        }
        assertEquals("File must contain an array of JSON objects", e.message)
    }

    @Test
    fun `document missing _id is rejected with index`() {
        val e = assertThrows(JsonImportService.ImportException::class.java) {
            service.validate("""[{"_id":"a"},{"name":"no-id"}]""")
        }
        assertEquals("Document at index 1 is missing required '_id' field", e.message)
    }

    @Test
    fun `non-object array element is rejected`() {
        val e = assertThrows(JsonImportService.ImportException::class.java) {
            service.validate("""[["_id"]]""")
        }
        assertEquals("Document at index 0 is not a JSON object", e.message)
    }
}
