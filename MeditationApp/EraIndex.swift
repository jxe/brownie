import Foundation

/// An era is a tag (usually an emoji) that groups the meditations of one period.
/// Membership lives in each file's tags; `eras.json` only records which tags are eras,
/// newest first, and when each one started.
struct Era: Codable, Hashable {
    var tag: String
    var started: String  // yyyy-MM-dd
}

struct EraIndex {
    static let filename = "eras.json"
    static let timelessTag = "timeless"

    /// Newest first. The first era is the current one.
    var eras: [Era] = []

    var current: Era? { eras.first }

    func isEraTag(_ tag: String) -> Bool {
        eras.contains { $0.tag == tag }
    }

    static func load() -> EraIndex {
        let directory = FileManager.default.meditationsDirectory
        let url = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Not downloaded yet: iCloud leaves a `.eras.json.icloud` placeholder. Ask for it;
            // the watcher refreshes the list once it lands.
            let placeholder = directory.appendingPathComponent(".\(filename).icloud")
            if FileManager.default.fileExists(atPath: placeholder.path) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
            return EraIndex()
        }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var data: Data?
        var coordinationError: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            data = try? Data(contentsOf: coordinatedURL)
        }
        guard let data, let eras = try? JSONDecoder().decode([Era].self, from: data) else {
            print("Brownie could not read \(filename)")
            return EraIndex()
        }
        return EraIndex(eras: eras)
    }

    func save() {
        guard FileManager.default.meditationStorageIsAvailable else { return }
        let url = FileManager.default.meditationsDirectory.appendingPathComponent(Self.filename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(eras) else { return }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                print("Save error: \(error)")
            }
        }
        if let coordinationError {
            print("Save coordination error: \(coordinationError)")
        }
    }

    static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// The `yyyy-MM-dd` date a meditation was made: its filename prefix, else its modification date.
    static func dateString(for url: URL) -> String {
        let name = url.lastPathComponent
        if let range = name.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            return String(name[range])
        }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: modified)
    }
}
