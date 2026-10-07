import Testing
import Foundation
import ClefFoundationModels

@Suite("Clef Endpoint & Model Topology Tests")
struct ClefEndpointTests {

    // MARK: - ClefModel Tests

    @Test("ClefModel workersAIIdentifier maps to official Cloudflare catalog strings")
    func testClefModelIdentifiers() {
        #expect(ClefModel.clef.workersAIIdentifier == "@cf/cloudflare/clef")
        #expect(ClefModel.clefFlash.workersAIIdentifier == "@cf/cloudflare/clef-flash")
    }

    @Test("ClefModel rawValue and display names are properly formed")
    func testClefModelDisplayNamesAndRawValues() {
        #expect(ClefModel.clef.rawValue == "clef")
        #expect(ClefModel.clefFlash.rawValue == "clef-flash")

        #expect(ClefModel.clef.displayName == "Cloudflare Clef (27B)")
        #expect(ClefModel.clefFlash.displayName == "Cloudflare Clef-Flash (9B)")

        #expect(ClefModel.allCases.count == 2)
        #expect(ClefModel.allCases.contains(.clef))
        #expect(ClefModel.allCases.contains(.clefFlash))
    }

    @Test("ClefModel Codable roundtrip matches JSON specification")
    func testClefModelCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for model in ClefModel.allCases {
            let data = try encoder.encode(model)
            let decoded = try decoder.decode(ClefModel.self, from: data)
            #expect(decoded == model)
        }
    }

    // MARK: - ClefEndpoint URL Formulation Tests

    @Test("ClefEndpoint.workersAI generates correct REST URLs for clef and clef-flash")
    func testWorkersAIURLFormulation() {
        let flashEndpoint = ClefEndpoint.workersAI(accountID: "cf-acc-12345", model: .clefFlash)
        #expect(flashEndpoint.url.absoluteString == "https://api.cloudflare.com/client/v4/accounts/cf-acc-12345/ai/run/@cf/cloudflare/clef-flash")
        #expect(flashEndpoint.model == .clefFlash)
        #expect(flashEndpoint.modelIdentifier == "clef-flash")

        let clefEndpoint = ClefEndpoint.workersAI(accountID: "cf-acc-67890", model: .clef)
        #expect(clefEndpoint.url.absoluteString == "https://api.cloudflare.com/client/v4/accounts/cf-acc-67890/ai/run/@cf/cloudflare/clef")
        #expect(clefEndpoint.model == .clef)
        #expect(clefEndpoint.modelIdentifier == "clef")
    }

    @Test("ClefEndpoint.gateway generates AI Gateway routing URLs with account and gateway IDs")
    func testGatewayURLFormulation() {
        let flashGateway = ClefEndpoint.gateway(accountID: "team-prod", gatewayID: "mobile-edge", model: .clefFlash)
        #expect(flashGateway.url.absoluteString == "https://gateway.ai.cloudflare.com/v1/team-prod/mobile-edge/workers-ai/@cf/cloudflare/clef-flash")
        #expect(flashGateway.model == .clefFlash)
        #expect(flashGateway.modelIdentifier == "clef-flash")

        let clefGateway = ClefEndpoint.gateway(accountID: "team-prod", gatewayID: "heavy-edge", model: .clef)
        #expect(clefGateway.url.absoluteString == "https://gateway.ai.cloudflare.com/v1/team-prod/heavy-edge/workers-ai/@cf/cloudflare/clef")
        #expect(clefGateway.model == .clef)
        #expect(clefGateway.modelIdentifier == "clef")
    }

    @Test("ClefEndpoint.local targets local inference runner with default and custom ports")
    func testLocalURLFormulation() {
        let defaultLocal = ClefEndpoint.local()
        #expect(defaultLocal.url.absoluteString == "http://localhost:8000/v1/evaluate")
        #expect(defaultLocal.model == .clefFlash)
        #expect(defaultLocal.modelIdentifier == "clef-flash")

        let customPortLocal = ClefEndpoint.local(port: 9090, model: .clef)
        #expect(customPortLocal.url.absoluteString == "http://localhost:9090/v1/evaluate")
        #expect(customPortLocal.model == .clef)
        #expect(customPortLocal.modelIdentifier == "clef")
    }

    @Test("ClefEndpoint.custom preserves explicit URL and model mapping")
    func testCustomURLFormulation() {
        let customURL = URL(string: "https://inference.internal.corp/v1/systemone")!
        let customEndpoint = ClefEndpoint.custom(customURL, model: .clef)

        #expect(customEndpoint.url == customURL)
        #expect(customEndpoint.model == .clef)
        #expect(customEndpoint.modelIdentifier == "clef")
    }

    @Test("ClefEndpoint Equatable and Hashable conformance works across instances")
    func testEndpointHashableAndEquatable() {
        let ep1 = ClefEndpoint.workersAI(accountID: "acc1", model: .clefFlash)
        let ep2 = ClefEndpoint.workersAI(accountID: "acc1", model: .clefFlash)
        let ep3 = ClefEndpoint.workersAI(accountID: "acc2", model: .clefFlash)

        #expect(ep1 == ep2)
        #expect(ep1 != ep3)

        var set = Set<ClefEndpoint>()
        set.insert(ep1)
        set.insert(ep2)
        set.insert(ep3)
        #expect(set.count == 2)
    }
}
