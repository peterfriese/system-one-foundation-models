import ClefFoundationModels
import Foundation
import FoundationModels

let url = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Examples/Quickstarts/ClefQuickstart/sample.jpg")
let session = LanguageModelSession(model: ClefLanguageModel())
let damaged = try await session.probability(of: "The parcel has visible exterior damage") { Attachment(imageURL: url) }
print("Damage probability: \(damaged)")
