import FoundationModels
import JevFoundationModels

let session = LanguageModelSession(model: JevLanguageModel())
let urgent = try await session.probability(
    of: "This support ticket requires immediate on-call escalation",
    state: "Production checkout returning HTTP 502 across us-east-1 for 14 minutes."
)
print("Urgent escalation probability: \(urgent)")
