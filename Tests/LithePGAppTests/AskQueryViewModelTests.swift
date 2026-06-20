import LithePGCore
import Testing

@testable import LithePGAppUI

@Suite("AskQueryViewModel")
struct AskQueryViewModelTests {
  @Test("draft button requires a prompt schema and idle state")
  func draftButtonAvailability() {
    #expect(AskQueryViewModel(prompt: "show customers", hasSchema: true).canDraft)
    #expect(!AskQueryViewModel(prompt: "   ", hasSchema: true).canDraft)
    #expect(!AskQueryViewModel(prompt: "show customers", isDrafting: true, hasSchema: true).canDraft)
    #expect(!AskQueryViewModel(prompt: "show customers", hasSchema: false).canDraft)
  }

  @Test("ready drafts expose preview and insert availability")
  func readyDraftPresentation() {
    let draft = AIQueryDraft(
      sql: "SELECT * FROM \"public\".\"customers\" LIMIT 100;",
      explanation: "Drafted a read-only SELECT.",
      referencedObjects: ["public.customers"],
      status: .ready,
      confidence: 0.75
    )

    let model = AskQueryViewModel(prompt: "show customers", draft: draft, hasSchema: true)

    #expect(model.sqlPreview == "SELECT * FROM \"public\".\"customers\" LIMIT 100;")
    #expect(model.statusMessage == "Drafted a read-only SELECT.")
    #expect(model.referencedObjectsText == "public.customers")
    #expect(model.canInsert)
  }

  @Test("errors and needs-model drafts disable insert")
  func nonReadyPresentationDisablesInsert() {
    let draft = AIQueryDraft(
      sql: "",
      explanation: "A local model is needed.",
      referencedObjects: [],
      status: .needsModel,
      confidence: 0
    )

    let errorModel = AskQueryViewModel(prompt: "predict churn", error: "No schema", hasSchema: false)
    #expect(errorModel.statusMessage == "No schema")
    #expect(!errorModel.canInsert)

    let needsModel = AskQueryViewModel(prompt: "predict churn", draft: draft, hasSchema: true)
    #expect(needsModel.statusMessage == "A local model is needed.")
    #expect(needsModel.sqlPreview.isEmpty)
    #expect(!needsModel.canInsert)
  }
}
