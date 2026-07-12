import SwiftUI

@main
struct JournalismWorkflowHubApp: App {
    @StateObject private var store = AppStore(configuration: AppDefaults.configuration)

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 720)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

private enum AppPresentationPhase {
    case splash
    case onboarding
    case app
}

struct AppRootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var phase: AppPresentationPhase = .splash
    @State private var didBootstrap = false

    var body: some View {
        Group {
            switch phase {
            case .splash:
                SplashScreenView()
            case .onboarding:
                OnboardingFlowView(onFinished: {
                    phase = .app
                })
            case .app:
                MainShellView(onOpenSetup: {
                    store.reopenOnboarding()
                    phase = .onboarding
                })
            }
        }
        .background(AppPalette.background.ignoresSafeArea())
        .onAppear {
            activateApplicationWindow()
        }
        .onChange(of: phase, initial: false) { _, _ in
            activateApplicationWindow()
        }
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            try? await Task.sleep(for: .milliseconds(850))
            phase = store.shouldShowOnboarding ? .onboarding : .app
        }
    }

    private func activateApplicationWindow() {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: \.canBecomeKey)?.makeKeyAndOrderFront(nil)
        }
    }
}

struct MainShellView: View {
    @EnvironmentObject private var store: AppStore
    let onOpenSetup: () -> Void

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView()
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    store.goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(!store.canNavigateBack)
                .help("Go to the previous page")

                Button {
                    store.goForward()
                } label: {
                    Label("Forward", systemImage: "chevron.right")
                }
                .disabled(!store.canNavigateForward)
                .help("Go to the next page")
            }

            ToolbarItemGroup(placement: .automatic) {
                Button("Refresh") {
                    store.reloadAll()
                }

                Button("Setup") {
                    onOpenSetup()
                }

                Button("Run") {
                    store.runSelectedWorkflow()
                }
                .disabled(store.selectedWorkflow == nil || store.isRunning)
            }
        }
    }
}

struct SplashScreenView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.92, blue: 0.86),
                    Color(red: 0.84, green: 0.88, blue: 0.84),
                    Color(red: 0.79, green: 0.85, blue: 0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "tray.full")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(Color(red: 0.15, green: 0.23, blue: 0.23))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Journalism Workflow Hub")
                            .font(.system(size: 34, weight: .semibold, design: .serif))
                            .foregroundStyle(Color(red: 0.13, green: 0.18, blue: 0.18))
                        Text("Local-first newsroom control surface")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color(red: 0.24, green: 0.31, blue: 0.31))
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(Color(red: 0.16, green: 0.27, blue: 0.27))
                    Text(store.isUsingDemoWorkspace ? "Opening demo workspace…" : "Loading workspace and launch state…")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color(red: 0.23, green: 0.30, blue: 0.30))
                }
            }
            .padding(36)
            .frame(maxWidth: 580, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 30, x: 0, y: 18)
        }
    }
}
