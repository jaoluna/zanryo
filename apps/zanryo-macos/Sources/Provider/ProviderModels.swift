import Foundation

enum ProviderId: String, Codable, CaseIterable, Sendable {
    case openAI = "openai"
    case claude
}

struct ProviderInstallation: Decodable, Equatable, Sendable {
    let provider: ProviderId
    let executablePath: String
}
