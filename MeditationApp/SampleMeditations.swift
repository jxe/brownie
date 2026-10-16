import Foundation

/// Installs the store's featured meditations once for new local users.
/// Existing libraries and user-deleted starters are left alone.
@MainActor
enum SampleMeditations {
    private static let installedVersionKey = "starterMeditationsVersion"
    private static let currentVersion = 1

    static func installIfNeeded() async {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: installedVersionKey) < currentVersion else { return }
        guard FileManager.default.meditationStorageIsConfigured else { return }
        guard FileManager.default.meditationStorageMode == .local else { return }

        // A pre-existing local library belongs to an upgrading user. Do not add
        // onboarding content to it merely because this version marker is new.
        guard FileManager.default.meditationFiles().isEmpty else {
            defaults.set(currentVersion, forKey: installedVersionKey)
            return
        }

        // Offline or nothing featured yet: try again next launch.
        guard let starters = try? await MeditationStore.shared.fetchStarters(), !starters.isEmpty else { return }

        for starter in starters {
            MeditationStore.shared.download(starter)
        }
        defaults.set(currentVersion, forKey: installedVersionKey)
    }
}
