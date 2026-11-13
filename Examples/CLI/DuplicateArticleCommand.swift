import Foundation
import FoundationModels
import SystemOneCore

// MARK: - Domain Models

struct Article: Identifiable, Sendable, Equatable, Hashable {
    let id: String
    let title: String
    let byline: String?
    let url: URL
    let excerpt: String

    init(
        id: String = UUID().uuidString,
        title: String,
        byline: String? = nil,
        url: URL,
        excerpt: String
    ) {
        self.id = id
        self.title = title
        self.byline = byline
        self.url = url
        self.excerpt = excerpt
    }
}

enum MatchReason: Sendable, Equatable {
    case deterministic(rule: String)
    case semantic(probability: Double, threshold: Double, judgement: NoulJudgement?)

    var description: String {
        switch self {
        case .deterministic(let rule):
            return "Layer 1 (Deterministic: \(rule))"
        case .semantic(let prob, let thresh, let judgement):
            let actionStr = judgement.map { " [\($0.decision.rawValue.uppercased())]" } ?? ""
            return String(format: "Layer 2 (System One: %.1f%% ≥ %.1f%% threshold)%@", prob * 100, thresh * 100, actionStr)
        }
    }
}

struct DuplicateMatch: Sendable, Equatable {
    let candidate: Article
    let reason: MatchReason
}

enum DeduplicationVerdict: Sendable, Equatable {
    case duplicate(DuplicateMatch)
    case unique
}

@Generable
struct ArticleDuplicateDecision: Sendable {
    @Guide(description: """
    Answer true only if the incoming article and the candidate are the SAME article content, \
    judged by substance rather than headline phrasing: the same topic, subject, entities, and key facts — \
    including the same article republished on a different domain, under a different headline. \
    Answer false ONLY when the articles are genuinely different content that merely share a topic or a similar title.
    """)
    var isDuplicate: Bool
}

// MARK: - Two-Layer Article Deduplicator

struct ArticleDeduplicator: Sendable {
    let provider: ConfiguredProvider
    let threshold: Double
    let policy: RoutingPolicy

    init(
        provider: ConfiguredProvider,
        threshold: Double = 0.60,
        policy: RoutingPolicy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85, undecidedBand: 0.35...0.65)
    ) {
        self.provider = provider
        self.threshold = threshold
        self.policy = policy
    }

    static func normalizeURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if let host = components.host, host.hasPrefix("www.") {
            components.host = String(host.dropFirst(4))
        }

        let trackingKeys: Set<String> = [
            "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
            "ref", "fbclid", "gclid", "msclkid", "mc_eid"
        ]

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

    static func normalizeTitle(_ title: String) -> String {
        title.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    func deterministicMatch(_ incoming: Article, in library: [Article]) -> DuplicateMatch? {
        let incomingNormURL = Self.normalizeURL(incoming.url)
        let incomingNormTitle = Self.normalizeTitle(incoming.title)

        for candidate in library {
            if Self.normalizeURL(candidate.url) == incomingNormURL {
                return DuplicateMatch(candidate: candidate, reason: .deterministic(rule: "Exact normalized URL match"))
            }

            if Self.normalizeTitle(candidate.title) == incomingNormTitle,
               let candidateByline = candidate.byline,
               let incomingByline = incoming.byline,
               candidateByline.caseInsensitiveCompare(incomingByline) == .orderedSame {
                return DuplicateMatch(candidate: candidate, reason: .deterministic(rule: "Exact title & byline match"))
            }
        }
        return nil
    }

    static func formatEvaluationState(incoming: Article, candidate: Article) -> String {
        """
        Incoming article:
        - Title: \(incoming.title)
        - Byline: \(incoming.byline ?? "Unknown")
        - URL: \(incoming.url.absoluteString)
        - Excerpt: \(incoming.excerpt)

        Candidate article:
        - Title: \(candidate.title)
        - Byline: \(candidate.byline ?? "Unknown")
        - URL: \(candidate.url.absoluteString)
        - Excerpt: \(candidate.excerpt)
        """
    }

    func evaluateSemanticPair(
        incoming: Article,
        candidate: Article
    ) async throws -> (isDuplicate: Bool, probability: Double, judgement: NoulJudgement) {
        try Task.checkCancellation()
        let session = provider.makeSession()
        let state = Self.formatEvaluationState(incoming: incoming, candidate: candidate)

        let response = try await session.respond(
            to: state,
            generating: ArticleDuplicateDecision.self
        )

        let probability = response.probability(for: "isDuplicate") ?? (response.content.isDuplicate ? 1.0 : 0.0)
        let judgement = response.judgement(for: "isDuplicate", policy: policy)

        let isFlagged: Bool
        switch judgement.decision {
        case .auto:
            isFlagged = (judgement.answer == true)
        case .confirm:
            isFlagged = (judgement.answer == true || probability >= threshold)
        case .escalate:
            isFlagged = true
        }

        return (isDuplicate: isFlagged, probability: probability, judgement: judgement)
    }

    func check(_ incoming: Article, against library: [Article]) async throws -> DeduplicationVerdict {
        if let match = deterministicMatch(incoming, in: library) {
            return .duplicate(match)
        }

        return try await withThrowingTaskGroup(of: DuplicateMatch?.self) { group in
            for candidate in library {
                group.addTask {
                    let evaluation = try await evaluateSemanticPair(incoming: incoming, candidate: candidate)
                    if evaluation.isDuplicate {
                        return DuplicateMatch(
                            candidate: candidate,
                            reason: .semantic(
                                probability: evaluation.probability,
                                threshold: threshold,
                                judgement: evaluation.judgement
                            )
                        )
                    }
                    return nil
                }
            }

            for try await match in group {
                if let match {
                    group.cancelAll()
                    return .duplicate(match)
                }
            }

            return .unique
        }
    }
}

// MARK: - Sample Corpus & Command Runner

enum DuplicateArticleCommand {
    private static func fixtureURL(host: String, path: String, queryItems: [URLQueryItem]? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = queryItems
        guard let built = components.url else {
            preconditionFailure("Invalid static fixture URL components for \(host)\(path)")
        }
        return built
    }

    private static let blogPostOriginal = Article(
        id: "art-peter-blog",
        title: "Agentic Coding with Xcode and Gemini CLI",
        byline: "Peter Friese",
        url: fixtureURL(host: "peterfriese.dev", path: "/blog/2026/agentic-coding-xcode-geminicli"),
        excerpt: "Autonomous coding agents are moving into production workflows. Here is how Gemini CLI pairs with Xcode for automated builds and testing."
    )

    private static let xArticleSyndication = Article(
        id: "art-peter-x",
        title: "Agentic Coding with Xcode and Gemini CLI",
        byline: "Peter Friese",
        url: fixtureURL(
            host: "x.com",
            path: "/peterfriese/status/2021555930412847567",
            queryItems: [
                URLQueryItem(name: "utm_source", value: "twitter"),
                URLQueryItem(name: "ref", value: "share")
            ]
        ),
        excerpt: "Autonomous coding agents are moving into production workflows. Here is how Gemini CLI pairs with Xcode for automated builds and testing."
    )

    private static let apNewsOriginal = Article(
        id: "art-ap-wire",
        title: "Apple unveils iPhone Duo, its foldable smartphone",
        byline: "Barbara Ortutay",
        url: fixtureURL(host: "apnews.com", path: "/article/apple-foldable-iphone-ternus-fd35312e6d894d5f3b055b3d62f22cd2"),
        excerpt: "Apple on Wednesday unveiled its latest generation of iPhones, including a widely anticipated foldable version called Duo. The company announced the device at its annual hardware event in Cupertino."
    )

    private static let kcbdLocalSyndication = Article(
        id: "art-kcbd-syndicated",
        title: "New iPhone lineup includes a foldable version called Duo",
        byline: "The Associated Press and Barbara Ortutay",
        url: fixtureURL(host: "www.kcbd.com", path: "/2026/09/10/new-iphone-lineup-includes-a-foldable-version-called-duo"),
        excerpt: "Apple on Wednesday unveiled its latest generation of iPhones, including a widely anticipated foldable version called Duo. The company announced the device at its annual hardware event in Cupertino."
    )

    private static let googlePixelFoldArticle = Article(
        id: "art-verge-pixel",
        title: "Google announces Pixel Fold 3 with Gemini Nano",
        byline: "David Pierce",
        url: fixtureURL(host: "theverge.com", path: "/2026/09/12/pixel-fold-3"),
        excerpt: "Google announced its third-generation foldable phone today at its Made by Google event in Mountain View, featuring on-device Gemini Nano multimodal intelligence."
    )

    static func run(provider: ConfiguredProvider, arguments: [String]) async {
        print("""
        ================================================================================
          System One CLI — Two-Layer Article Deduplication
          Provider: \(provider.provider.displayName)
          Endpoint: \(provider.endpointSummary)
        ================================================================================
        """)

        let deduplicator = ArticleDeduplicator(provider: provider)

        do {
            // Scenario 1: Deterministic Match
            printScenarioHeader(
                number: 1,
                title: "Identical Article on Different URLs",
                subtitle: "Same title & author on Personal Blog vs X Article. Matches deterministically."
            )
            printArticleComparison(incoming: xArticleSyndication, candidate: blogPostOriginal)
            let start1 = CFAbsoluteTimeGetCurrent()
            let result1 = try await deduplicator.check(xArticleSyndication, against: [blogPostOriginal])
            printVerdictResult(verdict: result1, durationMs: (CFAbsoluteTimeGetCurrent() - start1) * 1000.0)

            // Scenario 2: Rewritten Wire Story (Semantic Match)
            printScenarioHeader(
                number: 2,
                title: "Rewritten Wire Story (Semantic Substance Match)",
                subtitle: "Associated Press wire story republished by local affiliate with new headline & byline."
            )
            printArticleComparison(incoming: kcbdLocalSyndication, candidate: apNewsOriginal)
            print("   → Deterministic layer misses. Delegating to \(provider.provider.displayName)...\n")
            let start2 = CFAbsoluteTimeGetCurrent()
            let result2 = try await deduplicator.check(kcbdLocalSyndication, against: [apNewsOriginal])
            printVerdictResult(verdict: result2, durationMs: (CFAbsoluteTimeGetCurrent() - start2) * 1000.0)

            // Scenario 3: Distinct Story on Similar Topic
            printScenarioHeader(
                number: 3,
                title: "Different Story on Similar Topic (False Positive Control)",
                subtitle: "Foldable phone announcement from competitor (Google Pixel Fold). Must NOT match."
            )
            printArticleComparison(incoming: googlePixelFoldArticle, candidate: apNewsOriginal)
            let start3 = CFAbsoluteTimeGetCurrent()
            let result3 = try await deduplicator.check(googlePixelFoldArticle, against: [apNewsOriginal])
            printVerdictResult(verdict: result3, durationMs: (CFAbsoluteTimeGetCurrent() - start3) * 1000.0)

            // Scenario 4: Cooperative Cancellation
            printScenarioHeader(
                number: 4,
                title: "Swift 6 Cooperative Cancellation",
                subtitle: "Demonstrates clean CancellationError propagation without wrapping."
            )
            let task = Task {
                try await deduplicator.check(kcbdLocalSyndication, against: [apNewsOriginal])
            }
            task.cancel()
            do {
                _ = try await task.value
                print("   ℹ️ Task completed before cancellation took effect.")
            } catch is CancellationError {
                print("   ✅ SUCCESS: CancellationError caught cleanly.")
            }
        } catch {
            provider.failFastOnError(error)
        }
    }

    private static func printScenarioHeader(number: Int, title: String, subtitle: String) {
        print("\n--------------------------------------------------------------------------------")
        print("▶ SCENARIO \(number): \(title)")
        print("  \(subtitle)")
        print("--------------------------------------------------------------------------------")
    }

    private static func printArticleComparison(incoming: Article, candidate: Article) {
        print("""
        +-------------+------------------------------------------------------------------+
        | Attribute   | Incoming Article                                                 |
        +-------------+------------------------------------------------------------------+
        | Title       | \(incoming.title.prefix(64))
        | Byline      | \(incoming.byline ?? "None")
        | URL         | \(incoming.url.absoluteString.prefix(64))
        +-------------+------------------------------------------------------------------+
        | Attribute   | Candidate in Library                                             |
        +-------------+------------------------------------------------------------------+
        | Title       | \(candidate.title.prefix(64))
        | Byline      | \(candidate.byline ?? "None")
        | URL         | \(candidate.url.absoluteString.prefix(64))
        +-------------+------------------------------------------------------------------+
        """)
    }

    private static func printVerdictResult(verdict: DeduplicationVerdict, durationMs: Double) {
        let durationString = String(format: "%.1f ms", durationMs)
        switch verdict {
        case .duplicate(let match):
            print("⚡️ RESULT: ⚠️  DUPLICATE DETECTED (Evaluated in \(durationString))")
            print("   • Match Layer: \(match.reason.description)")
            print("   • Candidate:   \"\(match.candidate.title)\"")
        case .unique:
            print("⚡️ RESULT: ✅  UNIQUE ARTICLE (Evaluated in \(durationString))")
            print("   • No duplicate found in library. Safe to save directly.")
        }
    }
}
