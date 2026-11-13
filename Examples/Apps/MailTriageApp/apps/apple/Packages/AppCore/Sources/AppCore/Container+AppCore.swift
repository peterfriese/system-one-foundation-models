import Foundation
@_exported import FactoryKit

extension Container {
    public var keychainService: Factory<KeychainServiceProtocol> {
        self { KeychainService() }.singleton
    }

    public var backendConfigurationStore: Factory<BackendConfigurationStore> {
        self { BackendConfigurationStore() }.singleton
    }

    public var coreMLModelManager: Factory<CoreMLModelManager> {
        self { CoreMLModelManager() }.singleton
    }

    public var backendHealthProbeService: Factory<BackendHealthProbeServiceProtocol> {
        self { BackendHealthProbeService() }.singleton
    }

    public var triageEngine: Factory<TriageEngineProtocol> {
        self { TriageEngine() }.singleton
    }

    public var benchmarkTruthStore: Factory<BenchmarkTruthStoreProtocol> {
        self { BenchmarkTruthStore() }.singleton
    }

    @MainActor
    public var mailStore: Factory<MailStore> {
        self { MailStore() }.singleton
    }

    @MainActor
    public var benchmarkSessionStore: Factory<BenchmarkSessionStore> {
        self { BenchmarkSessionStore() }.singleton
    }
}

