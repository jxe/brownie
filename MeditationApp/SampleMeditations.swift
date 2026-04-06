import Foundation

/// Installs sample .med files on first launch
struct SampleMeditations {
    static func installIfNeeded() {
        let dir = FileManager.default.meditationsDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        if files.contains(where: { $0.pathExtension == "med" }) { return }

        let sample = """
        # Useless

        ~ person
          Stephanie \u{2640}
          Flo \u{2640}
          Ryan \u{2642}
          Sanya \u{2640}

        ~ why
          because I'm more of a rock
          because we recapture an innocence and simplicity
          because being self-authored is a flex
          because I'm a stationary thing they can account for
          because it adds peace to the world

        \u{00D7}5\u{1D110}28\u{2033}
          \u{00D7}5 I'm with {person}, not making progress. \u{00B7} Is it better {why}? 12\u{2033}
        """

        _ = FileManager.default.saveMeditation(sample, filename: "sample-useless.med")
    }
}
