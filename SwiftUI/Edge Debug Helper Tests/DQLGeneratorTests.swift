import Testing
@testable import Edge_Debug_Helper

struct DQLGeneratorTests {

@Test("Generate SELECT with all fields")
func testGenerateSelect() {
    let dql = DQLGenerator.generateSelect(
        collection: "crewMembers",
        fields: ["_id", "name", "age", "rank"]
    )
    #expect(dql == "SELECT _id, name, age, rank FROM crewMembers")
}

@Test("Generate SELECT * statement")
func testGenerateSelectAll() {
    let dql = DQLGenerator.generateSelectAll(collection: "crewMembers")
    #expect(dql == "SELECT * FROM crewMembers")
}

@Test("Generate INSERT with placeholders")
func testGenerateInsert() {
    let dql = DQLGenerator.generateInsert(
        collection: "crewMembers",
        fields: ["_id", "name", "age"]
    )
    #expect(dql.contains("INSERT INTO crewMembers DOCUMENTS"))
    #expect(dql.contains("\"_id\": \"<document-id>\""))
    #expect(dql.contains("\"name\": \"<value>\""))
    #expect(dql.contains("\"age\": \"<value>\""))
}

@Test("Generate INSERT with typed placeholders")
func testGenerateInsertWithTypes() {
    let fieldTypes: [String: TableCellValue] = [
        "_id": .string("123"),
        "name": .string("test"),
        "age": .number(25),
        "active": .bool(true),
        "metadata": .nested("{}")
    ]
    
    let dql = DQLGenerator.generateInsert(
        collection: "crewMembers",
        fields: ["_id", "name", "age", "active", "metadata"],
        fieldTypes: fieldTypes
    )
    
    #expect(dql.contains("\"_id\": \"<document-id>\""))
    #expect(dql.contains("\"name\": \"<value>\""))
    #expect(dql.contains("\"age\": 0"))
    #expect(dql.contains("\"active\": true"))
    #expect(dql.contains("\"metadata\": {}"))
}

@Test("Generate UPDATE excluding _id from SET")
func testGenerateUpdate() {
    let dql = DQLGenerator.generateUpdate(
        collection: "crewMembers",
        fields: ["_id", "name", "age"]
    )
    #expect(dql.contains("UPDATE crewMembers SET"))
    #expect(!dql.contains("SET _id"))
    #expect(dql.contains("name = \"<value>\""))
    #expect(dql.contains("age = \"<value>\""))
    #expect(dql.contains("WHERE _id = '<document-id>'"))
}

@Test("Generate UPDATE with typed placeholders")
func testGenerateUpdateWithTypes() {
    let fieldTypes: [String: TableCellValue] = [
        "_id": .string("123"),
        "name": .string("test"),
        "age": .number(25),
        "active": .bool(true)
    ]
    
    let dql = DQLGenerator.generateUpdate(
        collection: "crewMembers",
        fields: ["_id", "name", "age", "active"],
        fieldTypes: fieldTypes
    )
    
    #expect(dql.contains("UPDATE crewMembers SET"))
    #expect(dql.contains("name ="))
    #expect(dql.contains("age = 0"))
    #expect(dql.contains("active = true"))
    #expect(dql.contains("WHERE _id = '<document-id>'"))
    #expect(!dql.contains("SET _id"))
}

@Test("Generate DELETE with WHERE clause")
func testGenerateDelete() {
    let dql = DQLGenerator.generateDelete(collection: "crewMembers")
    #expect(dql == "DELETE FROM crewMembers WHERE _id = '<document-id>'")
}

@Test("Generate EVICT with WHERE clause")
func testGenerateEvict() {
    let dql = DQLGenerator.generateEvict(collection: "crewMembers")
    #expect(dql == "EVICT FROM crewMembers WHERE _id = '<document-id>'")
}

@Test("Generate statements with different collection names")
func testDifferentCollectionNames() {
    let collections = ["aircraft", "statusUpdates", "systemMetrics", "users"]
    
    for collection in collections {
        let selectDql = DQLGenerator.generateSelectAll(collection: collection)
        #expect(selectDql.contains("FROM \(collection)"))
        
        let deleteDql = DQLGenerator.generateDelete(collection: collection)
        #expect(deleteDql.contains("FROM \(collection)"))
    }
}

@Test("Generate UPDATE with only _id field should handle gracefully")
func testUpdateWithOnlyIdField() {
    let dql = DQLGenerator.generateUpdate(
        collection: "test",
        fields: ["_id"]
    )
    
    // Should have UPDATE and WHERE, but SET clause might be empty
    #expect(dql.contains("UPDATE test SET"))
    #expect(dql.contains("WHERE _id = '<document-id>'"))
}

}
