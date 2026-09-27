import Combine
import Foundation
import SwiftUI

// No inherited update channel. DiskOdds must not download or install upstream Radix releases.
// Preserve the settings interface until DiskOdds has its own signed release feed.
@MainActor
final class SoftwareUpdateModel: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var lastUpdateCheckDate: Date? = nil

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) { automaticallyChecksForUpdates = false }
    func restoreDefaultPreferences() { automaticallyChecksForUpdates = false }
    func checkForUpdates() { }
}

struct CheckForUpdatesView: View {
    @ObservedObject var softwareUpdates: SoftwareUpdateModel
    var body: some View {
        Button("DiskOdds updates are not configured") { }.disabled(true)
    }
}
