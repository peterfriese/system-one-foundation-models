import FoundationModels
import OpenAIFoundationModels

@Generable struct ExpenseDecision {
    var isApproved: Bool
    @Guide(.range(1...5)) var riskScore: Int
}
let session = LanguageModelSession(model: OpenAIDecisionsLanguageModel())
print(try await session.respond(to: "Team dinner receipt $142.50 with itemized invoice", generating: ExpenseDecision.self).content)
