import Foundation

@main
struct FileCoreTests {
    static var passed = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw NSError(domain: "TestFailure", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }; passed += 1; print("PASS \(message)")
    }
    static func rejects(_ name: String, _ body: () throws -> Void) throws {
        do { try body() } catch { passed += 1; print("PASS \(name)"); return }; throw NSError(domain: "TestFailure", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected rejection: \(name)"])
    }
    static func main() {
        do { try run() } catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    static func run() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory()).appendingPathComponent("ExplorerMac-tests-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let a = root.appendingPathComponent("源文件夹"), b = root.appendingPathComponent("目标文件夹")
        try fm.createDirectory(at: a, withIntermediateDirectories: false); try fm.createDirectory(at: b, withIntermediateDirectories: false)
        let source = a.appendingPathComponent("你好 world.txt"), data = Data("important content\n".utf8)
        try data.write(to: source)
        let (copy, _) = try FileCore.transfer(source, into: b, move: false)
        let copiedData = try Data(contentsOf: copy)
        try check(copiedData == data && FileCore.exists(source), "Copy preserves bytes and original")
        let (copy2, _) = try FileCore.transfer(source, into: b, move: false)
        try check(copy2.lastPathComponent == "你好 world (2).txt", "Collision preserves both names")
        let originalData = try Data(contentsOf: copy)
        try check(originalData == data, "Collision never overwrites original")
        let (sameCopy, _) = try FileCore.transfer(source, into: a, move: false)
        try check(sameCopy != source, "Copy within same folder creates a duplicate")
        try rejects("Move to same location is rejected") { _ = try FileCore.transfer(source, into: a, move: true) }
        try rejects("Recursive copy into child is rejected") { _ = try FileCore.transfer(root, into: a, move: false) }
        try rejects("Copy folder into itself is rejected") { _ = try FileCore.transfer(a, into: a, move: false) }
        let link = root.appendingPathComponent("shortcut")
        try fm.createSymbolicLink(at: link, withDestinationURL: a)
        try check(FileEntry(link).navigable, "Directory symlinks can be navigated")
        try rejects("Recursive copy via symlink is rejected") { _ = try FileCore.transfer(a, into: link, move: false) }
        let (moved, moveUndo) = try FileCore.transfer(sameCopy, into: b, move: true)
        let movedData = try Data(contentsOf: moved)
        try check(!FileCore.exists(sameCopy) && movedData == data, "Move retains bytes and removes original location")
        try FileCore.undo(moveUndo)
        try check(FileCore.exists(sameCopy) && !FileCore.exists(moved), "Undo move restores original location")
        let (renamed, renameUndo) = try FileCore.rename(source, name: "测试重命名.txt")
        try check(FileCore.exists(renamed) && !FileCore.exists(source), "Rename with Unicode works")
        try FileCore.undo(renameUndo)
        try check(FileCore.exists(source) && !FileCore.exists(renamed), "Undo rename restores exact name")
        try rejects("Rename collision is rejected") { _ = try FileCore.rename(source, name: sameCopy.lastPathComponent) }
        for name in ["", "  ", ".", "..", "bad/name", "bad:name", "bad\0name"] { try rejects("Invalid name \(name.debugDescription)") { try FileCore.validateName(name) } }
        let (caseURL, caseUndo) = try FileCore.rename(source, name: "你好 WORLD.txt")
        try check(caseURL.lastPathComponent == "你好 WORLD.txt", "Case-only rename works")
        try FileCore.undo(caseUndo)
        let names = try fm.contentsOfDirectory(atPath: a.path)
        try check(names.contains("你好 world.txt"), "Case-only rename can be undone")
        let (occupiedMove, occupiedUndo) = try FileCore.transfer(source, into: b, move: true)
        try Data("later file".utf8).write(to: source)
        try rejects("Undo refuses a new file at the original location") { try FileCore.undo(occupiedUndo) }
        try check(FileCore.exists(occupiedMove) && FileCore.exists(source), "Undo conflict leaves both files intact")
        let (changedMove, changedUndo) = try FileCore.transfer(sameCopy, into: b, move: true)
        try Data("changed since operation".utf8).write(to: changedMove)
        try rejects("Undo protects content modified after operation") { try FileCore.undo(changedUndo) }
        try rejects("Missing source produces an error") { _ = try FileCore.transfer(a.appendingPathComponent("missing.txt"), into: b, move: false) }
        let hidden = a.appendingPathComponent(".hidden"); try Data().write(to: hidden)
        try check(FileCore.exists(hidden), "Hidden paths remain valid file operations")
        let package = a.appendingPathComponent("Example.app"); try fm.createDirectory(at: package, withIntermediateDirectories: false)
        try check(FileEntry(package).isPackage && !FileEntry(package).navigable, "App bundles open as apps rather than folders")
        let nested = a.appendingPathComponent("Nested"); try fm.createDirectory(at: nested, withIntermediateDirectories: false); try data.write(to: nested.appendingPathComponent("child.txt"))
        let (folderCopy, _) = try FileCore.transfer(nested, into: b, move: false)
        let nestedData = try Data(contentsOf: folderCopy.appendingPathComponent("child.txt"))
        try check(nestedData == data, "Recursive folder copy retains child bytes")
        let (archive, _) = try FileCore.compress([source, nested], into: a)
        try check(FileCore.exists(archive), "ZIP compression creates an archive")
        let unzip = Process(); unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); unzip.arguments = ["-t", archive.path]; let pipe = Pipe(); unzip.standardOutput = pipe; unzip.standardError = pipe
        try unzip.run(); let archiveOutput = pipe.fileHandleForReading.readDataToEndOfFile(); unzip.waitUntilExit()
        try check(unzip.terminationStatus == 0 && String(data: archiveOutput, encoding: .utf8)?.contains("child.txt") == true, "ZIP integrity and nested file checks pass")
        print("\n\(passed) file-operation checks passed. Temporary fixtures removed on exit.")
    }
}
