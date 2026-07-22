import Foundation

enum BridgeDecodeError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case remote(code: String, message: String)
    case missingData
    case invalidUTF8
    case initializationFailed
}

extension BridgeDecodeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            "Unsupported bridge schema version \(version)"
        case let .remote(_, message):
            message
        case .missingData:
            "The bridge returned no dashboard data"
        case .invalidUTF8:
            "The bridge returned invalid UTF-8"
        case .initializationFailed:
            "The Zanryo bridge could not be initialized"
        }
    }
}

private struct SchemaProbe: Decodable {
    let schemaVersion: Int
}

private struct RemoteErrorPayload: Decodable {
    let code: String
    let message: String
}

private struct BridgeEnvelope<Payload: Decodable>: Decodable {
    let schemaVersion: Int
    let ok: Bool
    let data: Payload?
    let error: RemoteErrorPayload?
}

enum BridgeDecoder {
    private static let supportedSchema = 1

    static func decodeOptionalSnapshot(from data: Data) throws -> DashboardSnapshot? {
        try decodeEnvelope(DashboardSnapshot.self, from: data)
    }

    static func decodeInstallations(from data: Data) throws -> [ProviderInstallation] {
        try decodeEnvelope([ProviderInstallation].self, from: data) ?? []
    }

    private static func decodeEnvelope<Payload: Decodable>(
        _ payload: Payload.Type,
        from data: Data
    ) throws -> Payload? {
        let decoder = makeDecoder()
        let probe = try decoder.decode(SchemaProbe.self, from: data)
        guard probe.schemaVersion == supportedSchema else {
            throw BridgeDecodeError.unsupportedSchema(probe.schemaVersion)
        }

        let envelope = try decoder.decode(BridgeEnvelope<Payload>.self, from: data)
        guard envelope.ok else {
            let error = envelope.error
            throw BridgeDecodeError.remote(
                code: error?.code ?? "unknown_error",
                message: error?.message ?? "The Zanryo bridge returned an unknown error"
            )
        }
        return envelope.data
    }

    static func decodeRequiredSnapshot(from data: Data) throws -> DashboardSnapshot {
        guard let snapshot = try decodeOptionalSnapshot(from: data) else {
            throw BridgeDecodeError.missingData
        }
        return snapshot
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            if let date = formatter.date(from: value) {
                return date
            }

            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date: \(value)"
            )
        }
        return decoder
    }
}
