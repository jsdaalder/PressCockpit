import SwiftUI

@main
struct JournalismWorkflowHubApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1200, minHeight: 760)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView()
        }
        .background(AppPalette.background.ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Refresh") {
                    store.reloadAll()
                }
                Button("Run") {
                    store.runSelectedWorkflow()
                }
                .disabled(store.selectedWorkflow == nil || store.isRunning)
            }
        }
    }
}

