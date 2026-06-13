import EasyTierCore
import SwiftUI

@main
struct EasyTierApp: App {
    @State private var store = EasyTierAppStore()

    var body: some Scene {
        WindowGroup("EasyTier", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 900, minHeight: 620)
                .task { await store.load() }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Network") { store.addConfig() }
                    .keyboardShortcut("n")
                Button("Save") { store.save() }
                    .keyboardShortcut("s")
            }
        }

        MenuBarExtra("EasyTier", systemImage: store.instances.isEmpty ? "point.3.connected.trianglepath.dotted" : "point.3.connected.trianglepath.dotted.fill") {
            MenuBarContent()
                .environment(store)
        }
    }
}

private struct MenuBarContent: View {
    @Environment(EasyTierAppStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show EasyTier") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Text(store.instances.isEmpty ? "No running instances" : "\(store.instances.count) running")
        Button("Refresh") {
            Task { await store.refreshRuntime() }
        }
        Button("Stop All") {
            Task { await store.stopAll() }
        }
        Divider()
        Button("Quit") {
            NSApp.terminate(nil)
        }
    }
}
