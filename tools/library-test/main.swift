// Runs MeditationLibrary's sorting and moves on a COPY of a library folder, on the Mac,
// and checks nothing is lost. Never point it at the live iCloud folder.
//
//   tools/library-test/run.sh /tmp/brownie-copy
//
// Built from the app's own MeditationLibrary.swift, EraIndex.swift and
// FileManager+Meditations.swift, so it tests the code the app runs.

import CryptoKit
import Foundation

extension Notification.Name {
    static let meditationsDidChange = Notification.Name("meditationsDidChange")
    static let meditationStorageDidChange = Notification.Name("meditationStorageDidChange")
}

let args = CommandLine.arguments
guard args.count == 2 else {
    print("usage: library-test <copy of a library folder>")
    exit(2)
}
let root = URL(fileURLWithPath: args[1], isDirectory: true).standardizedFileURL
if root.path.contains("Mobile Documents") {
    print("Refusing to run on an iCloud folder. Copy it first.")
    exit(2)
}

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "  ok   \(what)" : "  FAIL \(what)")
    if !ok { failures += 1 }
}

let fm = FileManager.default
func medFiles(under dir: URL, skipping: Set<String> = []) -> [URL] {
    guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
    var out: [URL] = []
    for case let url as URL in e {
        let rel = url.path.replacingOccurrences(of: dir.path + "/", with: "")
        if skipping.contains(where: { rel.hasPrefix($0 + "/") }) { continue }
        if url.pathExtension == "med", !url.lastPathComponent.hasPrefix(".") { out.append(url) }
    }
    return out
}
func digest(_ url: URL) -> String {
    let data = (try? Data(contentsOf: url)) ?? Data()
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
func readIndex() -> [String: [String: Any]] {
    guard let data = try? Data(contentsOf: root.appendingPathComponent("library.json")),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let list = obj["meditations"] as? [[String: Any]] else { return [:] }
    return Dictionary(list.map { ($0["id"] as! String, $0) }, uniquingKeysWith: { a, _ in a })
}
func folderCounts() -> [String: Int] {
    var counts: [String: Int] = [:]
    for url in medFiles(under: root, skipping: [MeditationLibrary.backupFolder]) {
        let folder = MeditationLibrary.folderName(of: url, root: root)
        counts[folder.isEmpty ? "(top)" : folder, default: 0] += 1
    }
    return counts
}

// MARK: Before

let erasBefore = EraIndex.load(in: root)
let before = medFiles(under: root)
let hadIndex = fm.fileExists(atPath: root.appendingPathComponent("library.json").path)
print("Before: \(before.count) scripts, \(erasBefore.eras.count) eras, index: \(hadIndex)")
for (folder, n) in folderCounts().sorted(by: { $0.key < $1.key }) { print("  \(folder): \(n)") }

// What the old app would have said: era made by filename date, plus `kept`; Evergreen by tag.
var oldEras: [String: Set<String>] = [:]
var oldEvergreen = Set<String>()
var oldArchived = Set<String>()
for url in before {
    let name = MeditationLibrary.name(of: url)
    let inArchive = url.deletingLastPathComponent().lastPathComponent == "Archive"
    let made = MeditationLibrary.madeDay(name: name, url: url)
    var set = Set<String>()
    if let era = erasBefore.eras.first(where: { $0.started <= made }) { set.insert(era.id) }
    for era in erasBefore.eras where era.kept.contains(name) { set.insert(era.id) }
    let tags = MeditationLibrary.headerTags((try? String(contentsOf: url, encoding: .utf8)) ?? "")
    for era in erasBefore.eras where era.legacyTag.map({ tags.contains($0) }) == true { set.insert(era.id) }
    oldEras[name] = set
    if inArchive { oldArchived.insert(name) } else if tags.contains(EraIndex.timelessTag) { oldEvergreen.insert(name) }
}
var digestsBefore: [String: Int] = [:]
for url in before { digestsBefore[digest(url), default: 0] += 1 }

// MARK: Sort

let library = MeditationLibrary(root: { root })
let started = Date()
library.sync()
print(String(format: "\nFirst sync: %.2fs", Date().timeIntervalSince(started)))
for (folder, n) in folderCounts().sorted(by: { $0.key < $1.key }) { print("  \(folder): \(n)") }

let index = readIndex()
let after = medFiles(under: root, skipping: [MeditationLibrary.backupFolder])
var digestsAfter: [String: Int] = [:]
for url in after { digestsAfter[digest(url), default: 0] += 1 }

print("\nChecks")
check(after.count == before.count, "same number of scripts (\(before.count) → \(after.count))")
check(digestsAfter == digestsBefore, "every script's text is unchanged, none lost or doubled")
check(index.count == after.count, "one index entry per script (\(index.count))")
if !hadIndex {
    let backup = medFiles(under: root.appendingPathComponent(MeditationLibrary.backupFolder))
    var digestsBackup: [String: Int] = [:]
    for url in backup { digestsBackup[digest(url), default: 0] += 1 }
    check(digestsBackup == digestsBefore, "Before Folders/ holds a copy of everything (\(backup.count))")
    let topLeft = after.filter { MeditationLibrary.folderName(of: $0, root: root).isEmpty }
    check(erasBefore.eras.isEmpty || topLeft.isEmpty, "nothing left at the top (\(topLeft.count))")

    var eraMismatch: [String] = []
    var placeMismatch: [String] = []
    for (name, oldSet) in oldEras {
        guard let entry = index[name] else { eraMismatch.append("\(name): no entry with that id"); continue }
        let newSet = Set(entry["eras"] as? [String] ?? [])
        if newSet != oldSet { eraMismatch.append("\(name): \(oldSet.sorted()) → \(newSet.sorted())") }
        let folder = entry["folder"] as? String ?? ""
        let expected: String
        if oldArchived.contains(name) { expected = "Archive" }
        else if oldEvergreen.contains(name) { expected = "Evergreen" }
        else if let latest = erasBefore.eras.first(where: { oldSet.contains($0.id) }) { expected = erasBefore.folder(for: latest.id) ?? "?" }
        else { expected = erasBefore.eras.isEmpty ? "" : "Older" }
        if folder != expected { placeMismatch.append("\(name): expected \(expected), in \(folder)") }
    }
    check(eraMismatch.isEmpty, "ids are the old filenames, eras match what the old app showed")
    eraMismatch.prefix(20).forEach { print("       \($0)") }
    check(placeMismatch.isEmpty, "each script is in the folder of its latest era / Evergreen / Archive / Older")
    placeMismatch.prefix(20).forEach { print("       \($0)") }
    check(Set(index.values.filter { $0["folder"] as? String == "Evergreen" }.map { $0["id"] as! String }) == oldEvergreen,
          "Evergreen folder holds exactly the #timeless ones (\(oldEvergreen.count))")
}

let indexText = try? String(contentsOf: root.appendingPathComponent("library.json"), encoding: .utf8)
library.sync()
check(indexText == (try? String(contentsOf: root.appendingPathComponent("library.json"), encoding: .utf8))
      && medFiles(under: root, skipping: [MeditationLibrary.backupFolder]).count == after.count,
      "a second sync changes nothing")

// MARK: Moves (on the copy)

print("\nMoves")
let eras = EraIndex.load(in: root)
func entry(_ id: String) -> [String: Any]? { readIndex()[id] }
if let current = eras.current, eras.eras.count > 1,
   let past = library.files(archived: false).first(where: {
       !MeditationLibrary.isEvergreen($0) && !library.eras(of: $0).contains(current.id) }) {
    let id = library.id(for: past)
    let erasThen = Set(library.eras(of: past))
    library.bringAlong(past)
    let moved = library.url(forID: id)!
    check(MeditationLibrary.folderName(of: moved, root: root) == eras.folder(for: current.id)
          && fm.fileExists(atPath: moved.path) && !fm.fileExists(atPath: past.path),
          "Bring Along moves \(id) into the current era's folder")
    check(Set(library.eras(of: moved)) == erasThen.union([current.id]), "…and it still belongs to its old eras")
    library.sendBack(moved)
    let back = library.url(forID: id)!
    check(back.path == past.path && fm.fileExists(atPath: back.path), "Send Back returns it to \(MeditationLibrary.folderName(of: back, root: root))")

    library.setEvergreen(back, true)
    let green = library.url(forID: id)!
    check(MeditationLibrary.isEvergreen(green) && fm.fileExists(atPath: green.path), "Make Evergreen moves it to Evergreen/")
    library.setEvergreen(green, false)
    check(library.url(forID: id)!.path == past.path, "Not Evergreen puts it back")

    let renamed = library.rename(past, to: "\(MeditationLibrary.name(of: past))-renamed-test")!
    check(library.id(for: renamed) == id && fm.fileExists(atPath: renamed.path), "a rename keeps the id")
    _ = library.rename(renamed, to: MeditationLibrary.name(of: past))
    check(fm.fileExists(atPath: past.path), "…and renaming back works")
} else {
    print("  (skipped: needs two eras and a past meditation)")
}

// A new script dropped at the top joins the current era; a clashing name gets -2.
let dropped = root.appendingPathComponent("2026-11-28-dropped-on-the-mac.med")
try? "# Dropped on the Mac\n\nHello.\n".write(to: dropped, atomically: true, encoding: .utf8)
library.sync()
if let current = eras.current {
    let placed = library.url(forName: "2026-11-28-dropped-on-the-mac")
    check(placed.map { MeditationLibrary.folderName(of: $0, root: root) } == eras.folder(for: current.id)
          && placed.map { fm.fileExists(atPath: $0.path) } == true,
          "a new file at the top moves into the current era's folder")
    if let placed, let other = eras.eras.dropFirst().first.flatMap({ eras.folder(for: $0.id) }) {
        let clash = root.appendingPathComponent(other).appendingPathComponent(placed.lastPathComponent)
        try? fm.createDirectory(at: clash.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "# Same name\n".write(to: clash, atomically: true, encoding: .utf8)
        library.sync()
        check(!fm.fileExists(atPath: clash.path)
              && fm.fileExists(atPath: clash.deletingLastPathComponent().appendingPathComponent("2026-11-28-dropped-on-the-mac-2.med").path)
              && fm.fileExists(atPath: placed.path),
              "a second file with the same name in another folder becomes -2")
        library.delete(library.url(forName: "2026-11-28-dropped-on-the-mac-2")!)
    }
    library.delete(placed!)
    check(library.url(forName: "2026-11-28-dropped-on-the-mac") == nil
          || !fm.fileExists(atPath: library.url(forName: "2026-11-28-dropped-on-the-mac")!.path), "delete removes it")
}

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
