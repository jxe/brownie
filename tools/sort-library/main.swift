// One-off: sorts a Brownie library from the old flat layout into folders, on the Mac.
//
//   tools/sort-library/run.sh <library folder> --backup <dir outside iCloud>
//   tools/sort-library/run.sh <library folder> --dry-run
//
// Old layout: scripts at the top and in Archive/; Evergreen as a `#timeless` header tag; eras in
// eras.json with `kept` (brought-along filenames) and old era tags (`legacyTag`) in headers.
// New layout (see SYNTAX.md, "The library folder"): each script in the folder of the latest era
// it belongs to (named by the era's start date), or Evergreen/, Archive/, Older/; eras.json's
// `kept` lists only the eras a script belongs to beyond the one it was made in and its folder's.
// No script's text changes. It checks the result against what the old app showed.
//
// Built with the app's own MeditationLibrary.swift, EraIndex.swift and FileManager+Meditations.swift.

import CryptoKit
import Foundation

extension Notification.Name {
    static let meditationsDidChange = Notification.Name("meditationsDidChange")
    static let meditationStorageDidChange = Notification.Name("meditationStorageDidChange")
}

let fm = FileManager.default
var args = Array(CommandLine.arguments.dropFirst())
let dryRun = args.contains("--dry-run")
var backupDir: URL?
if let i = args.firstIndex(of: "--backup"), i + 1 < args.count {
    backupDir = URL(fileURLWithPath: (args[i + 1] as NSString).expandingTildeInPath, isDirectory: true)
}
guard let path = args.first, !path.hasPrefix("--"), dryRun || backupDir != nil else {
    print("usage: sort-library <library folder> (--dry-run | --backup <dir outside iCloud>)")
    exit(2)
}
let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)

func fail(_ message: String) -> Never {
    print("STOPPED: \(message)")
    exit(1)
}

// MARK: The old layout

struct OldEra {
    let id: String
    let started: String
    let kept: [String]
    let legacyTag: String?
}

let erasURL = root.appendingPathComponent(EraIndex.filename)
var oldEras: [OldEra] = []
if fm.fileExists(atPath: erasURL.path) {
    guard let data = try? Data(contentsOf: erasURL),
          let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        fail("can't read eras.json")
    }
    oldEras = list.map { e in
        let tag = (e["legacyTag"] as? String) ?? (e["tag"] as? String)
        return OldEra(id: (e["id"] as? String) ?? tag ?? (e["started"] as! String),
                      started: e["started"] as! String,
                      kept: e["kept"] as? [String] ?? [],
                      legacyTag: tag)
    }.sorted { $0.started > $1.started }
}

func headerTags(_ source: String) -> [String] {
    var tags: [String] = []
    var titleSeen = false
    for line in source.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else {
            if titleSeen { break }
            continue
        }
        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if words.allSatisfy({ $0 == "#" || ($0.hasPrefix("#") && $0.count > 1) }) {
            tags += words.filter { $0.count > 1 }.map { String($0.dropFirst()) }
            continue
        }
        if titleSeen { break }
        titleSeen = true
        tags += words.dropFirst().reversed().prefix { $0.hasPrefix("#") && $0.count > 1 }.map { String($0.dropFirst()) }
    }
    return tags
}

func listing(_ dir: URL) -> [String] {
    (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
}
let archiveDir = root.appendingPathComponent(MeditationLibrary.archiveFolder, isDirectory: true)
let placeholders = (listing(root) + listing(archiveDir)).filter { $0.hasPrefix(".") && $0.hasSuffix(".med.icloud") }
if !placeholders.isEmpty {
    fail("\(placeholders.count) scripts aren't downloaded yet (e.g. \(placeholders[0])). Download them first.")
}

struct Script {
    var url: URL
    let name: String
    let archived: Bool
    let made: String
    var member: Set<String>
    let evergreen: Bool
    let undated: Bool
    var newName: String
    var folder = ""
}

var scripts: [Script] = []
for (dir, archived) in [(root, false), (archiveDir, true)] {
    for item in listing(dir) where item.hasSuffix(".med") && !item.hasPrefix(".") {
        let url = dir.appendingPathComponent(item)
        let name = String(item.dropLast(4))
        let tags = headerTags((try? String(contentsOf: url, encoding: .utf8)) ?? "")
        let undated = name.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) == nil
        let made = EraIndex.dateString(for: url)
        // What the old app showed: the era made in, plus brought along, plus old era tags.
        var member = Set<String>()
        if let era = oldEras.first(where: { $0.started <= made }) { member.insert(era.id) }
        for era in oldEras where era.kept.contains(name) || era.legacyTag.map({ tags.contains($0) }) == true {
            member.insert(era.id)
        }
        scripts.append(Script(url: url, name: name, archived: archived, made: made, member: member,
                              evergreen: !archived && tags.contains("timeless"), undated: undated, newName: name))
    }
}
if scripts.filter({ !$0.archived }).isEmpty {
    fail("no scripts at the top: already sorted?")
}

// MARK: The plan

let newEras = EraIndex(eras: oldEras.map { old -> Era in
    var era = Era(started: old.started)
    era.id = old.id
    return era
})
var names = Set<String>()
// Live ones first, so a name in both keeps the live one.
scripts.sort { !$0.archived && $1.archived }
for i in scripts.indices {
    var name = scripts[i].name
    if names.contains(name) {
        var n = 2
        while names.contains("\(scripts[i].name)-\(n)") { n += 1 }
        name = "\(scripts[i].name)-\(n)"
    }
    names.insert(name)
    scripts[i].newName = name
    if scripts[i].archived {
        scripts[i].folder = MeditationLibrary.archiveFolder
    } else if scripts[i].evergreen {
        scripts[i].folder = MeditationLibrary.evergreenFolder
    } else {
        scripts[i].folder = MeditationLibrary.placement(Array(scripts[i].member), eras: newEras)
    }
}

// `kept`: every era it belongs to but wasn't made in and isn't the folder of. An undated script's
// made day comes from its file's creation date, which another device may see differently, so its
// eras are all written out.
var kept: [String: [String]] = [:]
for s in scripts {
    let madeEra = s.undated ? nil : newEras.eras.first { $0.started <= s.made }?.id
    let folderEra = newEras.era(inFolder: s.folder)?.id
    for id in s.member where id != madeEra && id != folderEra {
        kept[id, default: []].append(s.newName)
    }
}
var sortedEras = newEras
for i in sortedEras.eras.indices {
    sortedEras.eras[i].kept = (kept[sortedEras.eras[i].id] ?? []).sorted()
}

var counts: [String: Int] = [:]
for s in scripts { counts[s.folder.isEmpty ? "(top)" : s.folder, default: 0] += 1 }
print("\(scripts.count) scripts, \(oldEras.count) eras")
for (folder, n) in counts.sorted(by: { $0.key < $1.key }) { print("  \(folder): \(n)") }
let renamed = scripts.filter { $0.newName != $0.name }
for s in renamed { print("  rename (same name as another): \(s.folder)/\(s.name) → \(s.newName)") }
print("  undated, eras written out: \(scripts.filter(\.undated).map(\.name))")
print("  kept after: " + sortedEras.eras.map { "\($0.started): \($0.kept.count)" }.joined(separator: ", "))

if dryRun {
    print("\nDry run: nothing changed.")
    exit(0)
}

// MARK: Do it

func digest(_ url: URL) -> String {
    SHA256.hash(data: (try? Data(contentsOf: url)) ?? Data()).map { String(format: "%02x", $0) }.joined()
}
var digestsBefore: [String: Int] = [:]
for s in scripts { digestsBefore[digest(s.url), default: 0] += 1 }

let backup = backupDir!.appendingPathComponent("Documents-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
if backup.path.contains("Mobile Documents") { fail("put the backup outside iCloud") }
do {
    try fm.createDirectory(at: backupDir!, withIntermediateDirectories: true)
    try fm.copyItem(at: root, to: backup)
} catch {
    fail("backup failed: \(error)")
}
print("\nBacked up to \(backup.path)")

// eras.json first: if the moves are cut short, it's still right for what has moved, and the rest
// can be moved by hand.
sortedEras.save(in: root)
var moveFailures: [String] = []
for i in scripts.indices {
    let target = MeditationLibrary.fileURL(root, scripts[i].folder, scripts[i].newName)
    if target.path == scripts[i].url.path { continue }
    if MeditationLibrary.moveFile(scripts[i].url, to: target) {
        scripts[i].url = target
    } else {
        moveFailures.append(scripts[i].name)
    }
}

// MARK: Check

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "  ok   \(what)" : "  FAIL \(what)")
    if !ok { failures += 1 }
}
print("\nChecks")
check(moveFailures.isEmpty, "every move worked \(moveFailures.prefix(5))")
let library = MeditationLibrary(root: { root })
let after = library.files(archived: false) + library.files(archived: true)
var digestsAfter: [String: Int] = [:]
for url in after { digestsAfter[digest(url), default: 0] += 1 }
check(after.count == scripts.count, "same number of scripts (\(scripts.count) → \(after.count))")
check(digestsAfter == digestsBefore, "every script's text unchanged, none lost or doubled")
check(!listing(root).contains { $0.hasSuffix(".med") }, "nothing left at the top")
let erasNow = EraIndex.load(in: root)
var mismatches: [String] = []
for s in scripts {
    let now = Set(erasNow.eras(of: s.url))
    if now != s.member {
        mismatches.append("\(s.newName): \(s.member.sorted()) → \(now.sorted())")
    }
}
check(mismatches.isEmpty, "the app sees each script in the same eras as before")
mismatches.prefix(20).forEach { print("       \($0)") }
let evergreenNow = Set(after.filter(MeditationLibrary.isEvergreen).map(MeditationLibrary.name(of:)))
check(evergreenNow == Set(scripts.filter(\.evergreen).map(\.newName)), "Evergreen holds the #timeless ones (\(evergreenNow.count))")
let erasText = try? String(contentsOf: erasURL, encoding: .utf8)
library.sync()
check(erasText == (try? String(contentsOf: erasURL, encoding: .utf8))
      && library.files(archived: false).count + library.files(archived: true).count == after.count
      && !listing(root).contains { $0.hasSuffix(".med") },
      "the app's sync then changes nothing")
print(failures == 0 ? "\nDone, all checks passed." : "\n\(failures) check(s) failed. The backup is at \(backup.path).")
exit(failures == 0 ? 0 : 1)
