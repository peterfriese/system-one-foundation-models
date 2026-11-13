import FoundationModels
import LayaOnDevice

let severity = try await LanguageModelSession(model: LayaOnDeviceLanguageModel()).score(
    "Rate incident severity",
    levels: ["Low", "Medium", "High", "Critical"],
    state: "Database connection pool exhausted; queries timing out on checkout."
)
print("Severity: \(severity.mostLikelyLevel) (confidence: \(severity.confidence))")
