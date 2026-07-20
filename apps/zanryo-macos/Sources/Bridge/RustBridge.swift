import Foundation

protocol DashboardProviding: Sendable {
    func cached() async throws -> DashboardSnapshot?
    func refresh() async throws -> DashboardSnapshot
}

actor RustBridge: DashboardProviding {
    private final class Handle: @unchecked Sendable {
        let pointer: OpaquePointer

        init(pointer: OpaquePointer) {
            self.pointer = pointer
        }

        deinit {
            zanryo_destroy(pointer)
        }
    }

    private let handle: Handle

    init() throws {
        guard let pointer = zanryo_create() else {
            throw BridgeDecodeError.initializationFailed
        }
        handle = Handle(pointer: pointer)
    }

    func cached() async throws -> DashboardSnapshot? {
        let handle = handle
        return try await Task.detached(priority: .utility) {
            let data = try Self.copyJSON(from: zanryo_cached_json(handle.pointer))
            return try BridgeDecoder.decodeOptionalSnapshot(from: data)
        }.value
    }

    func refresh() async throws -> DashboardSnapshot {
        let handle = handle
        return try await Task.detached(priority: .utility) {
            let data = try Self.copyJSON(from: zanryo_refresh_json(handle.pointer))
            return try BridgeDecoder.decodeRequiredSnapshot(from: data)
        }.value
    }

    private nonisolated static func copyJSON(
        from pointer: UnsafeMutablePointer<CChar>?
    ) throws -> Data {
        guard let pointer else {
            throw BridgeDecodeError.missingData
        }
        defer { zanryo_string_free(pointer) }

        guard let value = String(validatingCString: pointer) else {
            throw BridgeDecodeError.invalidUTF8
        }
        return Data(value.utf8)
    }
}
