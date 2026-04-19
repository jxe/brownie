import Foundation

enum MeditationMetadataWriter {
    static func rewrite(source: String, title: String, tags: [String]) -> String {
        let lines = source.components(separatedBy: "\n")
        var titleSeen = false
        var metadataEnd = 0

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.hasPrefix("#") {
                break
            }
            if isPureTagLine(trimmed) {
                metadataEnd = index + 1
                continue
            }
            if !titleSeen {
                titleSeen = true
                metadataEnd = index + 1
                continue
            }
            break
        }

        let header = headerLine(title: title, tags: tags)
        var rebuilt: [String] = [header]
        if metadataEnd < lines.count {
            rebuilt.append(contentsOf: lines[metadataEnd...])
        }
        return rebuilt.joined(separator: "\n")
    }

    private static func headerLine(title: String, tags: [String]) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        var parts: [String] = ["#"]
        if !cleanTitle.isEmpty {
            parts.append(cleanTitle)
        }
        for tag in tags {
            parts.append("#\(tag)")
        }
        return parts.joined(separator: " ")
    }

    private static func isPureTagLine(_ trimmed: String) -> Bool {
        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !words.isEmpty else { return false }
        return words.allSatisfy { $0 == "#" || ($0.hasPrefix("#") && $0.count > 1) }
    }
}
