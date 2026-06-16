import EasyTierShared
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(EasyTierAppStore.self) private var store
    @State private var permissionController = PermissionController()
    @State private var showingModeSettings = false
    @State private var showingTOML = false
    @State private var tomlMode: TOMLSheet.Mode = .export
    @State private var draftConfig = NetworkConfig()
    @State private var draftConfigID: String?
    @State private var draftIsDirty = false
    @State private var tabTransitionEdge: Edge = .trailing

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                PermissionBanner(controller: permissionController)

                WorkspaceTabBar(selection: tabSelectionBinding)
                .padding([.horizontal, .top])

                Divider().padding(.top, 12)

                MotionSwitch(id: store.selectedTab.id, insertionEdge: tabTransitionEdge) {
                    workspaceContent
                }
            }
            .navigationTitle(navigationTitle)
            .toolbar { toolbar }
        }
        .task(id: store.selectedConfigID) {
            loadDraft(for: store.selectedConfigID)
        }
        .task {
            await permissionController.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await permissionController.refresh() }
            }
        }
        .sheet(isPresented: $showingModeSettings) {
            ModeSettingsSheet(mode: store.mode) { mode in
                Task { await store.applyMode(mode) }
            }
        }
        .sheet(isPresented: $showingTOML) {
            TOMLSheet(mode: tomlMode, initialText: tomlMode == .export ? store.exportSelectedTOML() : "") { text in
                if tomlMode == .import { store.importTOML(text) }
            }
        }
        .sheet(isPresented: $store.isShowingAbout) {
            AboutView()
        }
        .alert("EasyTier", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
        .windowMotion(role: .document)
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch store.selectedTab {
        case .status:
            StatusView()
        case .view:
            TrafficView()
        case .config:
            if let config = draftConfigBinding() {
                ConfigEditorView(config: config)
            } else if store.selectedConfigID != nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("No Network", systemImage: "network", description: Text("Create a network config to begin."))
            }
        case .logs:
            LogsView()
        }
    }

    private var sidebar: some View {
        @Bindable var store = store

        return List(selection: selectedConfigIDBinding) {
            Section("Networks") {
                ForEach(store.configs) { stored in
                    NetworkRow(stored: stored, state: connectionState(for: stored))
                        .tag(stored.id as String?)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    commitDraft(saveImmediately: true)
                    store.addConfig()
                } label: { Image(systemName: "plus") }
                    .help("Add network")
                Button(role: .destructive) {
                    draftIsDirty = false
                    Task { await store.deleteSelectedConfig() }
                } label: { Image(systemName: "trash") }
                .help("Delete selected network")
                .disabled(store.selectedConfigID == nil)
                Spacer()
                Button { Task { await store.refreshRuntime() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh runtime state")
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { showingModeSettings = true } label: {
                Label(store.mode.label, systemImage: "switch.2")
            }

            Button {
                commitDraft(saveImmediately: true)
                Task { await store.validateSelectedConfig() }
            } label: {
                Label("Check", systemImage: "checkmark.shield")
            }
            .disabled(store.selectedConfig == nil || store.isBusy)
            .help("Check selected network")

            Button {
                let runningInstanceToRestart = draftIsDirty ? store.selectedRunningInstance : nil
                commitDraft(saveImmediately: true)
                Task {
                    await permissionController.refresh()
                    guard permissionController.state == .enabled else {
                        store.clearHelperPermissionError()
                        return
                    }
                    if let runningInstanceToRestart {
                        await store.restartSelectedConfig(replacing: runningInstanceToRestart)
                    } else if selectedConfigIsRunning {
                        await store.stopSelectedConfig()
                    } else {
                        await store.runSelectedConfig()
                    }
                }
            } label: {
                Label(
                    connectionActionTitle,
                    systemImage: connectionActionSystemImage
                )
            }
            .disabled(store.selectedConfig == nil || store.isBusy || permissionController.state != .enabled)
            .help("Run selected network")

            Menu {
                Button("Import TOML") {
                    commitDraft(saveImmediately: true)
                    tomlMode = .import
                    showingTOML = true
                }
                Button("Export TOML") {
                    commitDraft(saveImmediately: true)
                    tomlMode = .export
                    showingTOML = true
                }
            } label: {
                Label("TOML", systemImage: "doc.text")
            }

            Button { store.isShowingAbout = true } label: {
                Label("About", systemImage: "info.circle")
            }
            .help("About EasyTier")
        }
    }

    private var navigationTitle: String {
        if draftConfigID == store.selectedConfigID {
            return draftConfig.network_name.isEmpty ? "EasyTier" : draftConfig.network_name
        }
        return store.selectedConfig?.network_name ?? "EasyTier"
    }

    private var selectedConfigIsRunning: Bool {
        if draftIsDirty, store.selectedConfigIsRunning { return true }
        guard let config = draftConfigID == store.selectedConfigID ? draftConfig : store.selectedConfig else { return false }
        return store.runningInstance(matching: config) != nil
    }

    private var selectedConfigNeedsRestart: Bool {
        draftIsDirty && store.selectedConfigIsRunning
    }

    private var connectionActionTitle: String {
        if store.isBusy { return "Working" }
        if selectedConfigNeedsRestart { return "Restart" }
        return selectedConfigIsRunning ? "Pause" : "Run"
    }

    private var connectionActionSystemImage: String {
        if store.isBusy { return "hourglass" }
        if selectedConfigNeedsRestart { return "arrow.clockwise" }
        return selectedConfigIsRunning ? "pause.fill" : "play.fill"
    }

    private func connectionState(for stored: StoredNetworkConfig) -> ConnectionGlyphState {
        if store.lastError != nil, store.selectedConfigID == stored.id { return .error }
        if store.isBusy, store.selectedConfigID == stored.id { return .connecting }
        if let instance = store.runningInstance(matching: stored.config) {
            return store.instanceIsFullyConnected(instance) ? .connected : .connecting
        }
        return .idle
    }

    private var selectedConfigIDBinding: Binding<String?> {
        Binding(
            get: { store.selectedConfigID },
            set: { newValue in
                commitDraft(saveImmediately: true)
                withAnimation(EasyTierMotion.content(reduceMotion: reduceMotion)) {
                    store.selectedConfigID = newValue
                    loadDraft(for: newValue)
                }
            }
        )
    }

    private var tabSelectionBinding: Binding<WorkspaceTab> {
        Binding(
            get: { store.selectedTab },
            set: { newValue in
                guard newValue != store.selectedTab else { return }
                tabTransitionEdge = newValue.motionIndex > store.selectedTab.motionIndex ? .trailing : .leading
                withAnimation(EasyTierMotion.selection(reduceMotion: reduceMotion)) {
                    store.selectedTab = newValue
                }
            }
        )
    }

    private func draftConfigBinding() -> Binding<NetworkConfig>? {
        guard let selectedID = store.selectedConfigID,
              store.configs.contains(where: { $0.id == selectedID })
        else { return nil }
        guard draftConfigID == selectedID else { return nil }

        return Binding(
            get: { draftConfig },
            set: { newValue in
                draftConfig = newValue
                draftIsDirty = true
            }
        )
    }

    private func loadDraft(for selectedID: String?) {
        guard let selectedID,
              let config = store.configs.first(where: { $0.id == selectedID })?.config
        else {
            draftConfig = NetworkConfig()
            draftConfigID = nil
            draftIsDirty = false
            return
        }
        guard draftConfigID != selectedID else { return }
        draftConfig = config
        draftConfigID = selectedID
        draftIsDirty = false
    }

    private func commitDraft(saveImmediately: Bool) {
        guard draftIsDirty, let draftConfigID else {
            if saveImmediately { store.save() }
            return
        }
        store.updateConfig(id: draftConfigID, with: draftConfig, saveImmediately: saveImmediately)
        self.draftConfigID = store.selectedConfigID
        draftIsDirty = false
    }
}

private struct WorkspaceTabBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: WorkspaceTab
    @Namespace private var selectionNamespace

    private let tabs = WorkspaceTab.allCases

    var body: some View {
        HStack(spacing: 12) {
            Text("View")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, alignment: .leading)

            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    tabButton(tab)

                    if index < tabs.count - 1 {
                        Divider()
                            .frame(height: 16)
                            .opacity(selection == tab || selection == tabs[index + 1] ? 0 : 0.55)
                    }
                }
            }
            .padding(2)
            .frame(maxWidth: .infinity)
            .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.primary.opacity(0.06), lineWidth: 1)
            }
            .animation(EasyTierMotion.selection(reduceMotion: reduceMotion), value: selection.id)
        }
    }

    private func tabButton(_ tab: WorkspaceTab) -> some View {
        let isSelected = selection == tab

        return Button {
            selection = tab
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(Rectangle())
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.82))
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.accentColor)
                    .matchedGeometryEffect(id: "workspace-tab-selection", in: selectionNamespace)
                    .shadow(color: Color.accentColor.opacity(0.22), radius: 4, y: 1)
            }
        }
        .buttonStyle(QuietPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.88))
        .accessibilityLabel(Text(tab.rawValue))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PermissionBanner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var controller: PermissionController

    var body: some View {
        VStack(spacing: 0) {
            if controller.state != .enabled {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.title3)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("EasyTier needs a privileged helper to create TUN devices.")
                            .font(.subheadline.weight(.semibold))
                        Text(controller.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if controller.state == .requiresApproval {
                        Button("Open Settings") { controller.openSystemSettings() }
                    }
                    switch controller.state {
                    case .requiresApproval:
                        Button("Refresh") { Task { await controller.refresh() } }
                            .disabled(controller.isBusy)
                    case .error:
                        Button("Repair Helper") { Task { await controller.repair() } }
                            .disabled(controller.isBusy)
                    default:
                        Button("Install Helper") {
                            Task { await controller.install() }
                        }
                        .disabled(controller.isBusy)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
                .transition(reduceMotion ? .opacity : .easyTierSlideFade(edge: .top, distance: 10))
                .task(id: controller.state) {
                    await refreshUntilHelperApproved()
                }
                Divider()
            }
        }
        .animation(EasyTierMotion.content(reduceMotion: reduceMotion), value: controller.state)
    }

    private func refreshUntilHelperApproved() async {
        guard controller.state == .requiresApproval else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: Self.approvalRefreshIntervalNanoseconds)
            } catch {
                return
            }
            guard controller.state == .requiresApproval else { return }
            await controller.refresh()
        }
    }

    private static let approvalRefreshIntervalNanoseconds: UInt64 = 2_000_000_000
}

private extension WorkspaceTab {
    var motionIndex: Int {
        WorkspaceTab.allCases.firstIndex(where: { $0.id == id }) ?? 0
    }
}

private struct NetworkRow: View {
    var stored: StoredNetworkConfig
    var state: ConnectionGlyphState

    var body: some View {
        HStack(spacing: 10) {
            NetworkStatusGlyph(state: state)
            VStack(alignment: .leading, spacing: 2) {
                Text(stored.config.network_name)
                    .lineLimit(1)
                Text(stored.source.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NetworkStatusGlyph: View {
    var state: ConnectionGlyphState

    var body: some View {
        ConnectionGlyph(state: state, size: 18, statusNodeColor: statusNodeColor)
            .frame(width: 18, height: 18)
        .frame(width: 22, height: 22)
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusNodeColor: Color {
        switch state {
        case .connected:
            return .green
        case .idle:
            return .red
        case .connecting, .error:
            return .orange
        }
    }

    private var accessibilityLabel: Text {
        switch state {
        case .connected:
            return Text("Running")
        case .idle:
            return Text("Stopped")
        case .connecting, .error:
            return Text("Unknown")
        }
    }
}
