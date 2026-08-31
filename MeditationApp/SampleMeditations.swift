import Foundation

/// Installs a small, general-purpose starter library once for new local users.
/// Existing libraries and user-deleted starters are left alone.
struct SampleMeditations {
    private static let installedVersionKey = "starterMeditationsVersion"
    private static let currentVersion = 1

    private static let starters: [(filename: String, content: String)] = [
        (
            "heart-focus.med",
            """
            # Heart Focus #feelings #starter

            ~ h
              objects around me
              someone I imagine
              someone nearby
              a work task

            ~ x
              I focus on my heart.
              Am I trying to be good? · Can I just be at peace?
              I try being heart centered with ~h

            ×7𝄐1′ ×5 ~x ··· 20″
            """
        ),
        (
            "tai-chi.med",
            """
            # Tai Chi #practice #daily #starter

            Neck stretch left · right · back · forward ·
            Neck roll 8″
            Reverse 8″
            Waist to the left 10″ right 10″ back 10″
            Knees · rotate in first 6″
            Reverse 6″
            Knees together squat down ·· back up · squat down ·· back up ··
            Arm swings with heels out 10″
            Second style, heels fixed 10″
            Finally, stand ···· ⏳40″ ··
            Other foot, stand ···· ⏳40″ ··
            Done!
            """
        ),
        (
            "self-trust.med",
            """
            # Self-Trust #orient #starter

            ~ a
              If I were safe to feel and ask the questions of my heart, what would I do?
              If I had my own back, what would I do?
              I'll hold nothing above taking care of myself. 1″ Does that make me feel free?
              Taking care of myself comes before all logistics. 1″ Does that make me feel free?
              If there was no excuse to neglect myself, what would I do?
              Can I have a kind of presence with myself, as a person of principle?
              Can I be a person of principle, noticing when there’s pain in my heart, and feeling it and holding myself?

            ×10𝄐28″ ×5 ~a 10″
            """
        ),
    ]

    static func installIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: installedVersionKey) < currentVersion else { return }
        guard FileManager.default.meditationStorageIsConfigured else { return }
        guard FileManager.default.meditationStorageMode == .local else { return }

        let existingFiles = FileManager.default.meditationFiles()
        let existingNames = Set(existingFiles.map(\.lastPathComponent))
        let starterNames = Set(starters.map(\.filename))

        // A pre-existing local library belongs to an upgrading user. Do not add
        // onboarding content to it merely because this version marker is new.
        if !existingNames.isEmpty && existingNames.isDisjoint(with: starterNames) {
            defaults.set(currentVersion, forKey: installedVersionKey)
            return
        }

        for starter in starters where !existingNames.contains(starter.filename) {
            _ = FileManager.default.saveMeditation(starter.content, filename: starter.filename)
        }

        let installedNames = Set(FileManager.default.meditationFiles().map(\.lastPathComponent))
        if starterNames.isSubset(of: installedNames) {
            defaults.set(currentVersion, forKey: installedVersionKey)
        }
    }
}
