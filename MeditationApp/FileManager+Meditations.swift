import Foundation

extension FileManager {
    var meditationsDirectory: URL {
        // Use iCloud container if available, fall back to local documents
        if let icloud = url(forUbiquityContainerIdentifier: "iCloud.com.joeedelman.meditations") {
            let dir = icloud.appendingPathComponent("Documents")
            if !fileExists(atPath: dir.path) {
                try? createDirectory(at: dir, withIntermediateDirectories: true)
            }
            return dir
        }
        // Fallback: local documents
        let docs = urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Meditations")
        if !fileExists(atPath: dir.path) {
            try? createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func meditationFiles() -> [URL] {
        guard let files = try? contentsOfDirectory(at: meditationsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "med" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
    }

    func readMeditation(at url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    func saveMeditation(_ content: String, filename: String) -> URL? {
        let name = filename.hasSuffix(".med") ? filename : "\(filename).med"
        let url = meditationsDirectory.appendingPathComponent(name)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("Save error: \(error)")
            return nil
        }
    }

    func deleteMeditation(at url: URL) {
        try? removeItem(at: url)
    }

    /// Moves any .med files from local Documents/Meditations to iCloud container
    func migrateToiCloud() {
        guard let icloud = url(forUbiquityContainerIdentifier: "iCloud.com.joeedelman.meditations") else { return }
        let icloudDocs = icloud.appendingPathComponent("Documents")
        if !fileExists(atPath: icloudDocs.path) {
            try? createDirectory(at: icloudDocs, withIntermediateDirectories: true)
        }

        let localDocs = urls(for: .documentDirectory, in: .userDomainMask).first!
        let localMed = localDocs.appendingPathComponent("Meditations")
        guard fileExists(atPath: localMed.path),
              let locals = try? contentsOfDirectory(at: localMed, includingPropertiesForKeys: nil)
                  .filter({ $0.pathExtension == "med" }),
              !locals.isEmpty else { return }

        for file in locals {
            let dest = icloudDocs.appendingPathComponent(file.lastPathComponent)
            if !fileExists(atPath: dest.path) {
                try? moveItem(at: file, to: dest)
            }
        }
    }
}
