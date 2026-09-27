// DiskOdds is based on Radix by Colin Kim. See LICENSE and DISKODDS-UPSTREAM.md.
import AppKit
import SwiftUI

@main
struct RadixApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var softwareUpdates = SoftwareUpdateModel()
    @State private var workspaceMode = 0

    var body: some Scene {
        Window("DiskOdds", id: "main") {
            DiskOddsWorkspaceView(mode: $workspaceMode)
                .environmentObject(appModel)
                .frame(minWidth: 1180, maxWidth: .infinity, minHeight: 680, maxHeight: .infinity)
        }
        .defaultSize(width: 1480, height: 900)
        .windowResizability(.contentMinSize)
        .commands {
            if workspaceMode == 1 {
                RadixCommands(appModel: appModel, scanState: appModel.scanState,
                              navigation: appModel.navigation, workspaceTour: appModel.workspaceTour)
            }
            CommandGroup(after: .help) {
                Button("Report DiskOdds Issue…", systemImage: "flag") {
                    if let url = URL(string: "https://github.com/kamatbot/DiskOdds/issues/new") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        Settings {
            SettingsView(softwareUpdates: softwareUpdates).environmentObject(appModel)
        }
    }
}
