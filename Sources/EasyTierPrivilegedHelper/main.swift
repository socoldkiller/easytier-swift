import Darwin
import EasyTierCore
import Foundation

final class PrivilegedService: NSObject, EasyTierPrivilegedServiceProtocol, @unchecked Sendable {
    private let client = StaticEasyTierFFIClient()
    private let encoder = JSONEncoder()

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
            try StaticEasyTierFFIClient.validateDirect(toml: toml)
            reply("ok", nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func run(configTOML: String, reply: @escaping (String?, String?) -> Void) {
        do {
            try StaticEasyTierFFIClient.validateDirect(toml: configTOML)
            try client.run(toml: configTOML)
            reply("ok", nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func stop(instanceNames: [String], reply: @escaping (String?, String?) -> Void) {
        run(reply: reply) { try client.stopSync(instanceNames: instanceNames) }
    }

    func retain(instanceNames: [String], reply: @escaping (String?, String?) -> Void) {
        run(reply: reply) { try client.retainSync(instanceNames: instanceNames) }
    }

    func listInstances(reply: @escaping (String?, String?) -> Void) {
        do {
            let instances = try client.listInstancesSync()
            reply(String(data: try encoder.encode(instances), encoding: .utf8) ?? "[]", nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func collectNetworkInfos(reply: @escaping (String?, String?) -> Void) {
        do {
            let infos = try client.collectNetworkInfoPayloadsSync()
            var object: [String: Any] = [:]
            for info in infos {
                object[info.key] = try JSONSerialization.jsonObject(with: Data(info.value.utf8))
            }
            let data = try JSONSerialization.data(withJSONObject: object)
            reply(String(data: data, encoding: .utf8) ?? "{}", nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    private func run(reply: @escaping (String?, String?) -> Void, _ operation: () throws -> Void) {
        do {
            try operation()
            reply("ok", nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
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
