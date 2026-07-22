import Foundation

enum ProviderId: String, Codable, CaseIterable, Hashable, Sendable {
    case openAI = "openai"
    case claude

    var displayName: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .claude:
            "Claude"
        }
    }

    var statusOrder: Int {
        switch self {
        case .openAI:
            0
        case .claude:
            1
        }
    }

    var glyphResourceName: String {
        switch self {
        case .openAI:
            "openai-provider-glyph"
        case .claude:
            "claude-provider-glyph"
        }
    }
}

struct ProviderInstallation: Decodable, Equatable, Sendable {
    let provider: ProviderId
    let executablePath: String
}
