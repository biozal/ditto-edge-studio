import Testing
@testable import Ditto_Edge_Studio

@Suite("DQL editor model reconciliation")
struct DQLTextReconciliationTests {
    @Test(.tags(.fast))
    func `Focused history selection can return to the last typed query`() {
        var reconciliation = DQLTextReconciliation()
        let typed = "SELECT * FROM cars"
        let history = "SELECT * FROM trucks"
        reconciliation.recordEditorChange(typed)

        let appliesHistory = reconciliation.shouldApply(modelText: history, editorText: typed, isFocused: true)
        #expect(appliesHistory)
        let restoresTyped = reconciliation.shouldApply(modelText: typed, editorText: history, isFocused: true)
        #expect(restoresTyped)
    }

    @Test(.tags(.fast))
    func `Repeated model renders preserve in-flight focused input`() {
        var reconciliation = DQLTextReconciliation()
        reconciliation.recordEditorChange("SELECT")

        let overwritesInput = reconciliation.shouldApply(modelText: "SELECT", editorText: "SELECT *", isFocused: true)
        #expect(!overwritesInput)
        reconciliation.recordEditorChange("SELECT *")
        let reappliesMatchingText = reconciliation.shouldApply(modelText: "SELECT *", editorText: "SELECT *", isFocused: true)
        #expect(!reappliesMatchingText)
    }

    @Test(.tags(.fast))
    func `A programmatic replacement becomes the baseline for subsequent renders`() {
        var reconciliation = DQLTextReconciliation()
        reconciliation.recordEditorChange("SELECT * FROM cars")
        let appliesReplacement = reconciliation.shouldApply(
            modelText: "SELECT * FROM trucks",
            editorText: "SELECT * FROM cars",
            isFocused: true
        )
        #expect(appliesReplacement)

        let overwritesSubsequentInput = reconciliation.shouldApply(
            modelText: "SELECT * FROM trucks",
            editorText: "SELECT * FROM trucks WHERE",
            isFocused: true
        )
        #expect(!overwritesSubsequentInput)
    }

    @Test(.tags(.fast))
    func `An unfocused editor accepts the model even when it repeats the baseline`() {
        var reconciliation = DQLTextReconciliation()
        reconciliation.recordEditorChange("SELECT")

        let appliesModel = reconciliation.shouldApply(modelText: "SELECT", editorText: "SELECT *", isFocused: false)
        #expect(appliesModel)
    }
}
