import EasyTierSupport
import Foundation

public final class PrivilegedEasyTierClient: EasyTierCoreClient, @unchecked Sendable {
    private let fallback: StaticEasyTierFFIClient

    public init(fallback: StaticEasyTierFFIClient = StaticEasyTierFFIClient()) {
        self.fallback = fallback
    }

    public func version() async throws -> String {
        if (try? await pingHelper()) == true { return "EasyTier privileged helper" }
        return try await fallback.version()
    }

    public func validate(toml: String) async throws {
        do {
            try await callHelper { service, reply in
                service.validate(toml: toml, reply: reply)
            }
        } catch PrivilegedHelperError.unavailable {
            // The helper is only a lightweight privilege boundary; the main app still owns FFI validation.
        }
        try await fallback.validate(toml: toml)
    }

    public func run(config: NetworkConfig) async throws {
        try await fallback.run(config: config)
    }

    public func stop(instanceNames: [String]) async throws {
        try await fallback.stop(instanceNames: instanceNames)
    }

    public func retain(instanceNames: [String]) async throws {
        try await fallback.retain(instanceNames: instanceNames)
    }

    public func listInstances() async throws -> [NetworkInstance] {
        try await fallback.listInstances()
    }

    public func collectNetworkInfos() async throws -> [String: NetworkInstanceRunningInfo] {
        try await fallback.collectNetworkInfos()
    }

    public func callJSONRPC(service: String, method: String, domain: String?, payload: String) async throws -> String {
        try await fallback.callJSONRPC(service: service, method: method, domain: domain, payload: payload)
    }

    public func startConfigServerClient(url: URL) async throws {
        try await fallback.startConfigServerClient(url: url)
    }

    public func stopConfigServerClient() async throws {
        try await fallback.stopConfigServerClient()
    }

    public func isConfigServerClientConnected() async throws -> Bool {
        try await fallback.isConfigServerClientConnected()
    }

    public func repairUserStateDirectory(uid: Int32, gid: Int32, home: String) async throws {
        try await callHelper { service, reply in
            service.repairUserStateDirectory(uid: uid, gid: gid, home: home, reply: reply)
        }
    }

    public func pingHelper() async throws -> Bool {
        do {
            _ = try await helperPingPayload()
            return true
        } catch PrivilegedHelperError.unavailable {
            return false
        }
    }

    public func helperPingPayload() async throws -> String {
        do {
            return try await callHelperReturningPayload { service, reply in service.ping(reply: reply) }
        } catch PrivilegedHelperError.unavailable {
            throw PrivilegedHelperError.unavailable
        }
    }

    private func callHelper(_ body: @escaping (EasyTierPrivilegedServiceProtocol, @escaping (String?, String?) -> Void) -> Void) async throws {
        _ = try await callHelperReturningPayload(body)
    }

    private func callHelperReturningPayload(_ body: @escaping (EasyTierPrivilegedServiceProtocol, @escaping (String?, String?) -> Void) -> Void) async throws -> String {
        let connection = Self.makeConnection()
        defer { connection.invalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            let state = HelperCallState(connection: connection, continuation: continuation)

            DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
                state.finish(.failure(PrivilegedHelperError.helperReported("Privileged helper did not respond within 15 seconds.")))
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                state.finish(.failure(PrivilegedHelperError.unavailable))
            }
            guard let service = proxy as? EasyTierPrivilegedServiceProtocol else {
                state.finish(.failure(PrivilegedHelperError.unavailable))
                return
            }
            body(service) { payload, error in
                if let error, !error.isEmpty {
                    state.finish(.failure(PrivilegedHelperError.helperReported(error)))
                } else {
                    state.finish(.success(payload ?? ""))
                }
            }
        }
    }

    private static func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(
            machServiceName: EasyTierPrivilegedHelperConstants.machServiceName,
            options: [.privileged]
        )
        connection.remoteObjectInterface = NSXPCInterface(with: EasyTierPrivilegedServiceProtocol.self)
        connection.resume()
        return connection
    }
}

private final class HelperCallState: @unchecked Sendable {
    private let lock = NSLock()
    private var didFinish = false
    private let connection: NSXPCConnection
    private let continuation: CheckedContinuation<String, Error>

    init(connection: NSXPCConnection, continuation: CheckedContinuation<String, Error>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()

        connection.invalidate()
        switch result {
        case let .success(payload):
            continuation.resume(returning: payload)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}
