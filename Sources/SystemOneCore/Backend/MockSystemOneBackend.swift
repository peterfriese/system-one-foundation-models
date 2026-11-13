import Foundation

/// A mock backend enabling offline, deterministic automated testing without live network services or GPU hardware.
public struct MockSystemOneBackend: SystemOneBackend, Sendable {
    public let id: UUID
    private let handler: @Sendable (SystemOneRequest) async throws -> SystemOneResponse

    public init(
        id: UUID = UUID(),
        fixedResponse: SystemOneResponse = SystemOneResponse(model: "mock-systemone", answers: [:])
    ) {
        self.id = id
        self.handler = { _ in fixedResponse }
    }

    public init(
        id: UUID = UUID(),
        handler: @escaping @Sendable (SystemOneRequest) async throws -> SystemOneResponse
    ) {
        self.id = id
        self.handler = handler
    }

    public func evaluate(request: SystemOneRequest) async throws -> SystemOneResponse {
        try await handler(request)
    }
}
