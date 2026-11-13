import FoundationModels
import GeminiFoundationModels

let session = LanguageModelSession(model: GeminiLanguageModel())
let fraudProb = try await session.probability(
    of: "This transaction requires manual fraud review",
    state: "New account purchased $4,800 in gift cards from 3 mismatched IPs in 90 seconds."
)
print("Fraud review probability: \(fraudProb.formatted(.percent.precision(.fractionLength(1))))")
