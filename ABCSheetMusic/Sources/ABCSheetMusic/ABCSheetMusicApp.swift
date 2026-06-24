import SwiftUI

@main
struct ABCSheetMusicApp: App {
    init() {
        if CommandLine.arguments.contains("--self-test") {
            Task { @MainActor in
                await BridgeSelfTest.run()
                NSApp.terminate(nil)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("12 Keys") {
                    NotificationCenter.default.post(name: .generate12Keys, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let generate12Keys = Notification.Name("generate12Keys")
}