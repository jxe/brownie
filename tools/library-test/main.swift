// Tries the app's library moves (Bring Along, Send Back, Evergreen, rename, a file dropped at
// the top, a clashing name) on a COPY of an already sorted library folder, on the Mac.
//
//   tools/library-test/run.sh /tmp/brownie-copy
//
// Built from the app's own MeditationLibrary.swift, EraIndex.swift and FileManager+Meditations.swift.

import Foundation

extension Notification.Name {
    static let meditationsDidChange = Notification.Name("meditationsDidChange")
    static let meditationStorageDidChange = Notification.Name("meditationStorageDidChange")
}

guard CommandLine.arguments.count == 2 else {
    print("usage: library-test <copy of a sorted library folder>")
    exit(2)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
if root.resolvingSymlinksInPath().path.contains("Mobile Documents") {
    print("Refusing to run on an iCloud folder. Copy it first.")
    exit(2)
}

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "  ok   \(what)" : "  FAIL \(what)")
    if !ok { failures += 1 }
}
let fm = FileManager.default
let library = MeditationLibrary(root: { root })
func eras() -> EraIndex { EraIndex.load(in: root) }
func folder(_ url: URL) -> String { MeditationLibrary.folderName(of: url, root: root) }

let index = eras()
print("Moves")
if let current = index.current, index.eras.count > 1,
   let past = library.files(archived: false).first(where: {
       !MeditationLibrary.isEvergreen($0) && !index.eras(of: $0).contains(current.id) && !index.eras(of: $0).isEmpty }) {
    let name = MeditationLibrary.name(of: past)
    let erasThen = Set(index.eras(of: past))
    library.bringAlong(past)
    let moved = library.url(forName: name)!
    check(folder(moved) == index.folder(for: current.id) && !fm.fileExists(atPath: past.path),
          "Bring Along moves \(name) into the current era's folder")
    check(Set(eras().eras(of: moved)) == erasThen.union([current.id]), "…and it still belongs to its old eras")
    library.sendBack(moved)
    let back = library.url(forName: name)!
    check(back.path == past.path && Set(eras().eras(of: back)) == erasThen, "Send Back returns it to \(folder(back)), same eras")

    library.bringAlong(past)
    let along = library.url(forName: name)!
    library.setEvergreen(along, true)
    let green = library.url(forName: name)!
    check(MeditationLibrary.isEvergreen(green) && Set(eras().eras(of: green)) == erasThen.union([current.id]),
          "Make Evergreen moves it to Evergreen/ and keeps its eras")
    library.setEvergreen(green, false)
    check(folder(library.url(forName: name)!) == index.folder(for: current.id), "Not Evergreen puts it back in the current era")
    library.archive(library.url(forName: name)!)
    check(folder(library.url(forName: name)!) == MeditationLibrary.archiveFolder, "Archive moves it to Archive/")
    library.unarchive(library.url(forName: name)!)
    check(folder(library.url(forName: name)!) == index.folder(for: current.id), "Unarchive puts it back")
    library.sendBack(library.url(forName: name)!)
    check(library.url(forName: name)!.path == past.path && Set(eras().eras(of: past)) == erasThen, "…and Send Back undoes it all")

    let renamed = library.rename(past, to: "\(name)-renamed-test")!
    check(fm.fileExists(atPath: renamed.path) && Set(eras().eras(of: renamed)) == erasThen, "a rename keeps its eras")
    _ = library.rename(renamed, to: name)
    check(fm.fileExists(atPath: past.path), "…and renaming back works")
} else {
    print("  (skipped: needs two eras and a past meditation)")
}

let keptBefore = try? String(contentsOf: root.appendingPathComponent(EraIndex.filename), encoding: .utf8)
let dropped = root.appendingPathComponent("2026-11-28-dropped-on-the-mac.med")
try? "# Dropped on the Mac\n\nHello.\n".write(to: dropped, atomically: true, encoding: .utf8)
library.sync()
if let current = index.current, let placed = library.url(forName: "2026-11-28-dropped-on-the-mac") {
    check(folder(placed) == index.folder(for: current.id), "a new file at the top moves into the current era's folder")
    if let other = index.eras.dropFirst().first.flatMap({ index.folder(for: $0.id) }) {
        let clash = root.appendingPathComponent(other).appendingPathComponent(placed.lastPathComponent)
        try? "# Same name\n".write(to: clash, atomically: true, encoding: .utf8)
        library.sync()
        let two = root.appendingPathComponent(other).appendingPathComponent("2026-11-28-dropped-on-the-mac-2.med")
        check(!fm.fileExists(atPath: clash.path) && fm.fileExists(atPath: two.path) && fm.fileExists(atPath: placed.path),
              "the same name in another folder becomes -2")
        library.delete(two)
    }
    library.delete(placed)
    check(library.url(forName: "2026-11-28-dropped-on-the-mac") == nil, "delete removes it")
} else {
    check(false, "a new file at the top moves into the current era's folder")
}
check(keptBefore == (try? String(contentsOf: root.appendingPathComponent(EraIndex.filename), encoding: .utf8)),
      "eras.json is as it was after all that")

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
