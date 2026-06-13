import EasyTierCore
import SwiftUI

struct StatusView: View {
    @Environment(EasyTierAppStore.self) private var store

    private var instance: NetworkInstance? { store.selectedRunningInstance }
    private var members: [NetworkMemberStatus] { store.selectedMemberStatuses }
    private var runtimeError: String? {
        if let error = instance?.error_msg, !error.isEmpty { return error }
        if let error = instance?.detail?.error_msg, !error.isEmpty { return error }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let runtimeError {
                ErrorBanner(message: runtimeError)
            }

            if instance == nil {
                ContentUnavailableView(
                    "No Running Network",
                    systemImage: "powerplug",
                    description: Text("Run the selected network to see its members.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if members.isEmpty {
                ContentUnavailableView(
                    "No Member Information",
                    systemImage: "person.2.slash",
                    description: Text(runtimeError ?? "EasyTier is running, but runtime member details have not arrived yet.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                memberTable
            }
        }
        .padding()
    }

    private var header: some View {
        HStack(spacing: 10) {
            StatusBadge(title: "Network", value: instance?.name ?? store.selectedConfig?.network_name ?? "-", systemImage: "network")
            StatusBadge(title: "Members", value: "\(members.count)", systemImage: "person.2")
            StatusBadge(title: "Device", value: instance?.detail?.dev_name ?? "-", systemImage: "dot.radiowaves.left.and.right")
            StatusBadge(title: "Mode", value: store.mode.label, systemImage: "switch.2")
            Spacer(minLength: 0)
        }
    }

    private var memberTable: some View {
        Table(members) {
            TableColumn("Member") { member in
                HStack(spacing: 8) {
                    Image(systemName: member.memberSystemImage)
                        .foregroundStyle(member.memberIconColor)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.hostname)
                            .lineLimit(1)
                        Text("Peer \(member.peerID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            TableColumn("IPv4") { member in
                Text(member.virtualIPv4)
                    .monospacedDigit()
            }
            TableColumn("Route") { member in
                Text(member.routeCost)
            }
            TableColumn("Tunnel") { member in
                Text(member.tunnelProto)
            }
            TableColumn("Latency") { member in
                Text(member.latency)
                    .monospacedDigit()
            }
            TableColumn("Upload") { member in
                Text(member.uploadTotal)
                    .monospacedDigit()
            }
            TableColumn("Download") { member in
                Text(member.downloadTotal)
                    .monospacedDigit()
            }
            TableColumn("Loss") { member in
                Text(member.lossRate)
                    .monospacedDigit()
            }
            TableColumn("NAT") { member in
                Text(member.natType)
            }
            TableColumn("Version") { member in
                Text(member.version)
                    .lineLimit(1)
            }
        }
    }
}

private extension NetworkMemberStatus {
    var memberSystemImage: String {
        if isLocal { return "macbook" }
        if isPublicServer { return "server.rack" }
        return "desktopcomputer"
    }

    var memberIconColor: Color {
        if isLocal { return Color.accentColor }
        if isPublicServer { return Color.green }
        return Color.secondary
    }
}

private struct StatusBadge: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value.isEmpty ? "-" : value)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ErrorBanner: View {
    var message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
