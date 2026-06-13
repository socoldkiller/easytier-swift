import Foundation

public enum TOMLCodecError: LocalizedError, Equatable {
    case invalidLine(String)
    case invalidValue(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidLine(line):
            "Could not parse TOML line: \(line)"
        case let .invalidValue(value):
            "Could not parse TOML value: \(value)"
        }
    }
}

public enum NetworkConfigTOMLCodec {
    public static func encode(_ config: NetworkConfig) -> String {
        let config = config.normalized()
        var lines: [String] = []

        lines.append("instance_name = \(quote(config.network_name.isEmpty ? config.instance_id : config.network_name))")
        lines.append("instance_id = \(quote(config.instance_id))")
        lines.append("dhcp = \(config.dhcp)")
        if !config.dhcp, !config.virtual_ipv4.isEmpty {
            lines.append("ipv4 = \(quote(config.virtual_ipv4))")
        }
        if let hostname = config.hostname, !hostname.isEmpty {
            lines.append("hostname = \(quote(hostname))")
        }
        if !config.listener_urls.isEmpty {
            lines.append("listeners = \(array(config.listener_urls))")
        }
        if !config.mapped_listeners.isEmpty {
            lines.append("mapped_listeners = \(array(config.mapped_listeners))")
        }
        if config.enable_manual_routes, !config.routes.isEmpty {
            lines.append("routes = \(array(config.routes))")
        }
        if !config.exit_nodes.isEmpty {
            lines.append("exit_nodes = \(array(config.exit_nodes))")
        }
        if let mtu = config.mtu {
            lines.append("mtu = \(mtu)")
        }

        lines.append("")
        lines.append("[network_identity]")
        lines.append("network_name = \(quote(config.network_name))")
        lines.append("network_secret = \(quote(config.network_secret ?? ""))")

        for peer in config.peer_urls where !peer.isEmpty {
            lines.append("")
            lines.append("[[peer]]")
            lines.append("uri = \(quote(peer))")
        }

        for cidr in config.proxy_cidrs where !cidr.isEmpty {
            lines.append("")
            lines.append("[[proxy_network]]")
            lines.append("cidr = \(quote(cidr))")
            lines.append("allow = [\"tcp\", \"udp\", \"icmp\"]")
        }

        if config.enable_vpn_portal {
            lines.append("")
            lines.append("[vpn_portal_config]")
            lines.append("client_network_addr = \(quote(config.vpn_portal_client_network_addr))")
            lines.append("client_network_len = \(config.vpn_portal_client_network_len)")
            lines.append("wireguard_listen = \(quote("wg://0.0.0.0:\(config.vpn_portal_listen_port)"))")
        }

        if config.enable_socks5 == true {
            lines.append("")
            lines.append("socks5_proxy = \(quote("socks5://127.0.0.1:\(config.socks5_port)"))")
        }

        for forward in config.port_forwards {
            lines.append("")
            lines.append("[[port_forward]]")
            lines.append("proto = \(quote(forward.proto))")
            lines.append("bind_addr = \(quote("\(forward.bind_ip):\(forward.bind_port)"))")
            lines.append("dst_addr = \(quote("\(forward.dst_ip):\(forward.dst_port)"))")
        }

        var flags: [String: Bool] = [:]
        set(&flags, "latency_first", config.latency_first)
        set(&flags, "use_smoltcp", config.use_smoltcp)
        set(&flags, "enable_ipv6", config.disable_ipv6.map { !$0 })
        set(&flags, "enable_kcp_proxy", config.enable_kcp_proxy)
        set(&flags, "disable_kcp_input", config.disable_kcp_input)
        set(&flags, "enable_quic_proxy", config.enable_quic_proxy)
        set(&flags, "disable_quic_input", config.disable_quic_input)
        set(&flags, "disable_p2p", config.disable_p2p)
        set(&flags, "p2p_only", config.p2p_only)
        set(&flags, "lazy_p2p", config.lazy_p2p)
        set(&flags, "bind_device", config.bind_device)
        set(&flags, "no_tun", config.no_tun)
        set(&flags, "enable_exit_node", config.enable_exit_node)
        set(&flags, "relay_all_peer_rpc", config.relay_all_peer_rpc)
        set(&flags, "need_p2p", config.need_p2p)
        set(&flags, "multi_thread", config.multi_thread)
        set(&flags, "proxy_forward_by_system", config.proxy_forward_by_system)
        set(&flags, "enable_encryption", config.disable_encryption.map { !$0 })
        set(&flags, "disable_tcp_hole_punching", config.disable_tcp_hole_punching)
        set(&flags, "disable_udp_hole_punching", config.disable_udp_hole_punching)
        set(&flags, "disable_upnp", config.disable_upnp)
        set(&flags, "enable_udp_broadcast_relay", config.enable_udp_broadcast_relay)
        set(&flags, "disable_sym_hole_punching", config.disable_sym_hole_punching)
        set(&flags, "accept_dns", config.enable_magic_dns)
        set(&flags, "private_mode", config.enable_private_mode)

        if !flags.isEmpty {
            lines.append("")
            lines.append("[flags]")
            for key in flags.keys.sorted() {
                lines.append("\(key) = \(flags[key] == true)")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    public static func decode(_ toml: String) throws -> NetworkConfig {
        var config = NetworkConfig()
        var section = "root"

        for rawLine in toml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line == "[network_identity]" {
                section = "network_identity"
                continue
            } else if line == "[[peer]]" {
                section = "peer"
                continue
            } else if line == "[[proxy_network]]" {
                section = "proxy_network"
                continue
            } else if line == "[flags]" {
                section = "flags"
                continue
            } else if line.hasPrefix("[") {
                section = "other"
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2 else { throw TOMLCodecError.invalidLine(line) }
            let key = parts[0]
            let value = parts[1]

            switch (section, key) {
            case (_, "instance_id"):
                config.instance_id = try parseString(value)
            case (_, "instance_name"):
                let name = try parseString(value)
                if config.network_name == "easytier" { config.network_name = name }
            case (_, "dhcp"):
                config.dhcp = try parseBool(value)
            case (_, "ipv4"):
                config.virtual_ipv4 = try parseString(value)
                config.dhcp = false
            case (_, "hostname"):
                config.hostname = try parseString(value)
            case (_, "listeners"):
                config.listener_urls = try parseStringArray(value)
            case (_, "mapped_listeners"):
                config.mapped_listeners = try parseStringArray(value)
            case (_, "routes"):
                config.routes = try parseStringArray(value)
                config.enable_manual_routes = !config.routes.isEmpty
            case (_, "exit_nodes"):
                config.exit_nodes = try parseStringArray(value)
            case (_, "mtu"):
                config.mtu = Int(value)
            case ("network_identity", "network_name"):
                config.network_name = try parseString(value)
            case ("network_identity", "network_secret"):
                config.network_secret = try parseString(value)
            case ("peer", "uri"):
                config.peer_urls.append(try parseString(value))
            case ("proxy_network", "cidr"):
                config.proxy_cidrs.append(try parseString(value))
            case ("flags", "latency_first"):
                config.latency_first = try parseBool(value)
            case ("flags", "disable_p2p"):
                config.disable_p2p = try parseBool(value)
            case ("flags", "no_tun"):
                config.no_tun = try parseBool(value)
            case ("flags", "accept_dns"), ("flags", "enable_magic_dns"):
                config.enable_magic_dns = try parseBool(value)
            case ("flags", "enable_ipv6"):
                config.disable_ipv6 = try !parseBool(value)
            case ("flags", "enable_encryption"):
                config.disable_encryption = try !parseBool(value)
            case ("flags", "private_mode"), ("flags", "enable_private_mode"):
                config.enable_private_mode = try parseBool(value)
            default:
                continue
            }
        }

        return config.normalized()
    }

    private static func set(_ flags: inout [String: Bool], _ key: String, _ value: Bool?) {
        if let value { flags[key] = value }
    }

    private static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func array(_ values: [String]) -> String {
        "[" + values.map(quote).joined(separator: ", ") + "]"
    }

    private static func stripComment(_ line: String) -> String {
        var inString = false
        var escaped = false
        var output = ""
        for character in line {
            if escaped {
                output.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                output.append(character)
                escaped = true
                continue
            }
            if character == "\"" { inString.toggle() }
            if character == "#", !inString { break }
            output.append(character)
        }
        return output
    }

    private static func parseString(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") else {
            throw TOMLCodecError.invalidValue(value)
        }
        let inner = trimmed.dropFirst().dropLast()
        return inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func parseBool(_ value: String) throws -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "true": true
        case "false": false
        default: throw TOMLCodecError.invalidValue(value)
        }
    }

    private static func parseStringArray(_ value: String) throws -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
            throw TOMLCodecError.invalidValue(value)
        }
        let body = trimmed.dropFirst().dropLast()
        var values: [String] = []
        var current = ""
        var inString = false
        var escaped = false

        for character in body {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                current.append(character)
                escaped = true
                continue
            }
            if character == "\"" { inString.toggle() }
            if character == ",", !inString {
                let part = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !part.isEmpty { values.append(try parseString(part)) }
                current = ""
            } else {
                current.append(character)
            }
        }

        let part = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !part.isEmpty { values.append(try parseString(part)) }
        return values
    }
}
