import Darwin
import EasyTierSupport
import Foundation

final class PrivilegedService: NSObject, EasyTierPrivilegedServiceProtocol, @unchecked Sendable {
    func ping(reply: @escaping (String?, String?) -> Void) {
        reply(EasyTierPrivilegedHelperConstants.pingPayload, nil)
    }

    func repairUserStateDirectory(uid: Int32, gid: Int32, home: String, reply: @escaping (String?, String?) -> Void) {
        do {
            let directory = URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("EasyTier", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            _ = chown(directory.path, uid_t(uid), gid_t(gid))
            _ = chmod(directory.path, S_IRWXU | S_IRGRP | S_IXGRP)
            reply("ok", nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func validate(toml: String, reply: @escaping (String?, String?) -> Void) {
        do {
            let config = try NetworkConfigTOMLCodec.decode(toml)
            try NetworkConfigValidator.validate(config)
            reply("ok", nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func run(configTOML: String, reply: @escaping (String?, String?) -> Void) {
        validate(toml: configTOML) { _, error in
            reply(nil, error ?? "EasyTier runtime is managed by the main app process.")
        }
    }

    func stop(instanceNames: [String], reply: @escaping (String?, String?) -> Void) {
        reply(nil, "EasyTier runtime is managed by the main app process.")
    }

    func retain(instanceNames: [String], reply: @escaping (String?, String?) -> Void) {
        reply(nil, "EasyTier runtime is managed by the main app process.")
    }

    func listInstances(reply: @escaping (String?, String?) -> Void) {
        reply(nil, "EasyTier runtime is managed by the main app process.")
    }

    func collectNetworkInfos(reply: @escaping (String?, String?) -> Void) {
        reply(nil, "EasyTier runtime is managed by the main app process.")
    }
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    private let service = PrivilegedService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: EasyTierPrivilegedServiceProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

let listener = NSXPCListener(machServiceName: EasyTierPrivilegedHelperConstants.machServiceName)
let delegate = HelperDelegate()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
