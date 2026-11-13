import FoundationModels
import LayaFoundationModels

let route = try await LanguageModelSession(model: LayaLanguageModel()).choice(
    "Select the team responsible for handling this request",
    options: ["billing", "engineering", "security"],
    state: "Customer charged twice on invoice #9920 after card retry."
)
print("Routed to \(route.value) (confidence: \(route.confidence))")
