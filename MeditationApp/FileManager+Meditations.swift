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

    var archiveDirectory: URL {
        let dir = meditationsDirectory.appendingPathComponent("Archive")
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

    func archivedMeditationFiles() -> [URL] {
        guard let files = try? contentsOfDirectory(at: archiveDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "med" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
    }

    func readMeditation(at url: URL) -> String? {
        // Coordinated read so iCloud downloads the latest content (if any) before we parse,
        // and so we play nicely with any other process / NSFilePresenter touching the file.
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: String?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = try? String(contentsOf: coordinatedURL, encoding: .utf8)
        }
        if let coordinationError {
            print("Read coordination error: \(coordinationError)")
        }
        return result
    }

    func saveMeditation(_ content: String, filename: String) -> URL? {
        let name = filename.hasSuffix(".med") ? filename : "\(filename).med"
        let url = meditationsDirectory.appendingPathComponent(name)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                try content.write(to: coordinatedURL, atomically: true, encoding: .utf8)
            } catch {
                writeError = error
            }
        }
        if let coordinationError {
            print("Save coordination error: \(coordinationError)")
            return nil
        }
        if let writeError {
            print("Save error: \(writeError)")
            return nil
        }
        return url
    }

    func deleteMeditation(at url: URL) {
        try? removeItem(at: url)
    }

    @discardableResult
    func archiveMeditation(at url: URL) -> URL? {
        moveMeditation(at: url, to: archiveDirectory)
    }

    @discardableResult
    func unarchiveMeditation(at url: URL) -> URL? {
        moveMeditation(at: url, to: meditationsDirectory)
    }

    private func moveMeditation(at url: URL, to destinationDirectory: URL) -> URL? {
        if !fileExists(atPath: destinationDirectory.path) {
            try? createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        }
        let originalName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = destinationDirectory.appendingPathComponent(url.lastPathComponent)
        var suffix = 1
        while fileExists(atPath: candidate.path) {
            let newName = "\(originalName)-\(suffix).\(ext)"
            candidate = destinationDirectory.appendingPathComponent(newName)
            suffix += 1
        }
        do {
            try moveItem(at: url, to: candidate)
            return candidate
        } catch {
            print("Move error: \(error)")
            return nil
        }
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
