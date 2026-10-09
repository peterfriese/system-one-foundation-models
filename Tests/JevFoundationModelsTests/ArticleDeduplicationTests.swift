import Testing
import Foundation
import FoundationModels
@testable import JevFoundationModels

// MARK: - Article Deduplication Decision Type for Foundation Models

@Generable
struct TestArticleDuplicateDecision {
    @Guide(description: """
    Answer true only if the incoming article and the candidate are the SAME article content, \
    judged by substance rather than headline phrasing: the same topic, subject, entities, and key facts — \
    including the same article republished on a different domain, under a different headline. \
    Answer false ONLY when the articles are genuinely different content that merely share a topic or a similar title.
    """)
    var isDuplicate: Bool
}

// MARK: - Article Deduplication Suite

@Suite("Article Deduplication & Telemetry Tests")
struct ArticleDeduplicationTests {

    // MARK: - Schema Translation

    @Test("ArticleDuplicateDecision schema translates to Jev noul primitive")
    func testArticleDuplicateDecisionSchema() throws {
        let translator = SchemaTranslator()
        let translation = try translator.translate(TestArticleDuplicateDecision.generationSchema)

        #expect(translation.questions.count == 1)
        guard case .noul(let instructions) = translation.questions["isDuplicate"] else {
            Issue.record("Expected 'isDuplicate' to translate to .noul")
            return
        }

        #expect(instructions.contains("judged by substance rather than headline phrasing"))
        #expect(instructions.contains("Answer true only if the incoming article and the candidate are the SAME article content"))
    }

    // MARK: - Response Telemetry & Extensions

    @Test("LanguageModelSession.Response extensions accurately parse probabilities and confidence")
    func testResponseExtensions() async throws {
        let mockTransport = MockJevTransport { _ in
            JevResponse(
                model: "jev-1.13.0",
                answers: [
                    "isDuplicate": JevAnswer(
                        type: "noul",
                        noul: 0.94,
                        confidence: 0.88,
                        probabilities: ["true": 0.94, "false": 0.06]
                    )
                ],
                usage: JevUsage(inputTokens: 520, outputTokens: 25)
            )
        }

        let model = JevLanguageModel(apiKey: "mock-key", transport: mockTransport)
        let session = LanguageModelSession(model: model)

        let response = try await session.respond(
            to: "Incoming: iPhone Duo\nCandidate: Foldable iPhone",
            generating: TestArticleDuplicateDecision.self
        )

        // Verify strongly-typed content
        #expect(response.content.isDuplicate == true)

        // Verify metadata access
        #expect(response.metadata["model"] != nil)
        #expect(response.metadata["probabilities"] != nil)
        #expect(response.metadata["confidence"] != nil)

        // Verify convenient probabilities accessor
        let probs = response.probabilities
        #expect(probs["isDuplicate"]?["true"] == 0.94)
        #expect(probs["isDuplicate"]?["false"] == 0.06)

        // Verify probability helper for boolean question
        let trueProb = response.probability(for: "isDuplicate")
        #expect(trueProb == 0.94)
        #expect(response.typedProbability(for: "isDuplicate") == 0.94)

        // Verify confidence helper
        let conf = response.confidence(for: "isDuplicate")
        #expect(conf == 0.88)
    }

    @Test("Multi-turn conversation metadata returns active turn metadata instead of turn 1")
    func testMultiTurnMetadataReturnsLatestTurn() async throws {
        actor TurnCounter {
            var count = 0
            func next() -> Int {
                count += 1
                return count
            }
        }

        let counter = TurnCounter()
        let mockTransport = MockJevTransport { _ in
            let turn = await counter.next()
            let prob = turn == 1 ? 0.20 : 0.95
            return JevResponse(
                model: "turn-\(turn)",
                answers: [
                    "isDuplicate": JevAnswer(
                        type: "noul",
                        noul: prob,
                        confidence: prob,
                        probabilities: ["true": prob, "false": 1.0 - prob]
                    )
                ],
                usage: JevUsage(inputTokens: 100, outputTokens: 10)
            )
        }

        let model = JevLanguageModel(apiKey: "mock-key", transport: mockTransport)
        let session = LanguageModelSession(model: model)

        let turn1 = try await session.respond(to: "Turn 1", generating: TestArticleDuplicateDecision.self)
        #expect(turn1.probability(for: "isDuplicate") == 0.20)

        let turn2 = try await session.respond(to: "Turn 2", generating: TestArticleDuplicateDecision.self)
        #expect(turn2.probability(for: "isDuplicate") == 0.95)
    }

    // MARK: - Calibrated Threshold Evaluation

    @Test("Calibrated threshold logic distinguishes true duplicates from borderline cases")
    func testThresholdCalibration() async throws {
        let threshold = 0.60

        // Case A: High probability wire reprint (0.93) -> Duplicate
        let highProbTransport = MockJevTransport { _ in
            JevResponse(
                model: "jev-1.13.0",
                answers: ["isDuplicate": JevAnswer(type: "noul", noul: 0.93)],
                usage: JevUsage(inputTokens: 500, outputTokens: 20)
            )
        }
        let highModel = JevLanguageModel(apiKey: "mock-key", transport: highProbTransport)
        let highSession = LanguageModelSession(model: highModel)
        let highResp = try await highSession.respond(to: "State A", generating: TestArticleDuplicateDecision.self)
        let highProb = highResp.probability(for: "isDuplicate") ?? 0.0
        #expect(highProb >= threshold)

        // Case B: Borderline related topic (0.55) -> Below threshold 0.60
        let borderlineTransport = MockJevTransport { _ in
            JevResponse(
                model: "jev-1.13.0",
                answers: ["isDuplicate": JevAnswer(type: "noul", noul: 0.55)],
                usage: JevUsage(inputTokens: 500, outputTokens: 20)
            )
        }
        let borderModel = JevLanguageModel(apiKey: "mock-key", transport: borderlineTransport)
        let borderSession = LanguageModelSession(model: borderModel)
        let borderResp = try await borderSession.respond(to: "State B", generating: TestArticleDuplicateDecision.self)
        let borderProb = borderResp.probability(for: "isDuplicate") ?? 0.0
        #expect(borderProb < threshold)

        // Case C: Distinct article (0.01) -> Below threshold 0.60
        let distinctTransport = MockJevTransport { _ in
            JevResponse(
                model: "jev-1.13.0",
                answers: ["isDuplicate": JevAnswer(type: "noul", noul: 0.01)],
                usage: JevUsage(inputTokens: 500, outputTokens: 20)
            )
        }
        let distinctModel = JevLanguageModel(apiKey: "mock-key", transport: distinctTransport)
        let distinctSession = LanguageModelSession(model: distinctModel)
        let distinctResp = try await distinctSession.respond(to: "State C", generating: TestArticleDuplicateDecision.self)
        let distinctProb = distinctResp.probability(for: "isDuplicate") ?? 0.0
        #expect(distinctProb < threshold)
    }

    // MARK: - Deterministic Normalization Rules (from blog post)

    @Test("Title normalization preserves punctuation and collapses whitespace")
    func testTitleNormalization() {
        func normalizeTitle(_ title: String) -> String {
            title.lowercased()
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
        }

        // Punctuation must be strictly preserved
        #expect(normalizeTitle("C++") != normalizeTitle("C"))
        #expect(normalizeTitle("State of AI 2025") != normalizeTitle("State of AI 2026"))

        // Whitespace and case are normalized
        #expect(normalizeTitle("  Agentic   Coding with  Xcode  ") == "agentic coding with xcode")
        #expect(normalizeTitle("Agentic Coding with Xcode") == "agentic coding with xcode")
    }

    @Test("URL normalization strips query tracking and trims trailing slashes")
    func testURLNormalization() {
        func normalizeURL(_ url: URL) -> String {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url.absoluteString.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }

            components.scheme = components.scheme?.lowercased()
            components.host = components.host?.lowercased()
            if let host = components.host, host.hasPrefix("www.") {
                components.host = String(host.dropFirst(4))
            }

            let trackingKeys: Set<String> = ["utm_source", "utm_medium", "utm_campaign", "ref", "fbclid"]
            if let queryItems = components.queryItems {
                let filtered = queryItems.filter { !trackingKeys.contains($0.name.lowercased()) }
                components.queryItems = filtered.isEmpty ? nil : filtered
            }

            var result = components.string ?? url.absoluteString
            while result.hasSuffix("/") {
                result.removeLast()
            }
            return result
        }

        let url1 = URL(string: "https://x.com/peterfriese/status/2021555930412847567?utm_source=twitter&ref=share")!
        let url2 = URL(string: "https://x.com/peterfriese/status/2021555930412847567/")!
        #expect(normalizeURL(url1) == "https://x.com/peterfriese/status/2021555930412847567")
        #expect(normalizeURL(url2) == "https://x.com/peterfriese/status/2021555930412847567")
    }
}
