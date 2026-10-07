import Foundation

public enum KeychainKey: String, Sendable, CaseIterable {
    case cloudflareAccountId = "cloudflareAccountId"
    case cloudflareApiToken = "cloudflareApiToken"
    case typesafeApiKey = "typesafeApiKey"
    case hostedVpcToken = "hostedVpcToken"
    case huggingFaceToken = "huggingFaceToken"
}
