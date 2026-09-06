import Foundation
import AppKit
import UniformTypeIdentifiers

struct FileEntry: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let isPackage: Bool
    let isLink: Bool
    let size: Int64
    let modified: Date
    let created: Date
    let kind: String
    let isImage: Bool
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var navigable: Bool { isDirectory && !isPackage }
    var sizeText: String { navigable ? "—" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
    static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
    init(_ url: URL) {
        self.url = url.standardizedFileURL
        let v = try? url.resourceValues(forKeys: Self.keys)
        let typeURL = v?.isSymbolicLink == true ? url.resolvingSymlinksInPath() : url
        let contentType = (try? typeURL.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: typeURL.pathExtension)
        var resolvedDirectory: ObjCBool = false
        if v?.isSymbolicLink == true { _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &resolvedDirectory) }
        isDirectory = (v?.isDirectory ?? false) || resolvedDirectory.boolValue
        isPackage = v?.isPackage ?? false
        isLink = v?.isSymbolicLink ?? false
        size = Int64(v?.fileSize ?? 0)
        modified = v?.contentModificationDate ?? .distantPast
        created = v?.creationDate ?? .distantPast
        isImage = contentType?.conforms(to: .image) ?? false
        kind = isDirectory && !isPackage ? (isLink ? "文件夹链接" : "文件夹") : (contentType?.localizedDescription ?? (url.pathExtension.isEmpty ? "文件" : url.pathExtension.uppercased() + " 文件"))
    }
}

enum FileFailure: LocalizedError {
    case invalidName, recursiveCopy, destinationExists, missingFile, sameLocation, changedSinceOperation
    var errorDescription: String? {
        switch self {
        case .invalidName: return "名称不能为空、不能为 . 或 ..，也不能包含 /、: 或空字符。"
        case .recursiveCopy: return "不能把文件夹复制或移动到它自身或它的子文件夹中。"
        case .destinationExists: return "目标位置已有同名文件，操作已停止，原文件保持不变。"
        case .missingFile: return "文件已不存在，或您没有访问它的权限。"
        case .sameLocation: return "文件已经位于目标文件夹中。"
        case .changedSinceOperation: return "该项目自操作后已被替换或修改，为保护后续更改，未执行撤销。"
        }
    }
}

enum UndoAction {
    case move(from: URL, to: URL)
    case trash(URL)
}
struct FileIdentity {
    let inode: UInt64?
    let device: UInt64?
    let modified: Date?
    let size: UInt64?
    let directory: Bool
    init(_ url: URL) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        inode = (attrs?[.systemFileNumber] as? NSNumber)?.uint64Value
        device = (attrs?[.systemNumber] as? NSNumber)?.uint64Value
        modified = attrs?[.modificationDate] as? Date
        size = (attrs?[.size] as? NSNumber)?.uint64Value
        directory = attrs?[.type] as? FileAttributeType == .typeDirectory
    }
    func matches(_ url: URL) -> Bool {
        let now = FileIdentity(url)
        return inode != nil && inode == now.inode && device == now.device && (directory || (size == now.size && modified == now.modified))
    }
}
struct UndoStep {
    let action: UndoAction
    let identity: FileIdentity
    static func move(from: URL, to: URL) -> UndoStep { UndoStep(action: .move(from: from, to: to), identity: FileIdentity(from)) }
    static func trash(_ url: URL) -> UndoStep { UndoStep(action: .trash(url), identity: FileIdentity(url)) }
}

enum FileCore {
    static let fm = FileManager.default
    static func validateName(_ name: String) throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || [".", ".."].contains(name) || name.contains("/") || name.contains(":") || name.contains("\0") { throw FileFailure.invalidName }
    }
    static func exists(_ url: URL) -> Bool { (try? fm.attributesOfItem(atPath: url.path)) != nil }
    static func uniqueURL(in folder: URL, name: String) -> URL {
        let first = folder.appendingPathComponent(name)
        if !exists(first) { return first }
        let entry = FileEntry(first)
        let ext = entry.navigable ? "" : first.pathExtension
        let stem = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        var index = 2
        while true {
            let result = folder.appendingPathComponent("\(stem) (\(index))" + (ext.isEmpty ? "" : ".\(ext)"))
            if !exists(result) { return result }; index += 1
        }
    }
    static func validateTransfer(_ source: URL, into folder: URL, move: Bool) throws {
        guard exists(source) else { throw FileFailure.missingFile }
        let src = source.resolvingSymlinksInPath().standardizedFileURL
        let dst = folder.resolvingSymlinksInPath().standardizedFileURL
        if FileEntry(source).navigable && (src.path == dst.path || dst.path.hasPrefix(src.path == "/" ? "/" : src.path + "/")) { throw FileFailure.recursiveCopy }
        if move && src.deletingLastPathComponent().path == dst.path { throw FileFailure.sameLocation }
    }
    static func transfer(_ source: URL, into folder: URL, move: Bool) throws -> (URL, UndoStep) {
        try validateTransfer(source, into: folder, move: move)
        let destination = uniqueURL(in: folder, name: source.lastPathComponent)
        if move { try fm.moveItem(at: source, to: destination) }
        else { try fm.copyItem(at: source, to: destination) }
        return (destination, move ? .move(from: destination, to: source) : .trash(destination))
    }
    static func rename(_ source: URL, name: String) throws -> (URL, UndoStep) {
        try validateName(name)
        let target = source.deletingLastPathComponent().appendingPathComponent(name)
        guard source != target else { return (source, .move(from: source, to: source)) }
        // Case-only renaming is supported on case-insensitive volumes by the filesystem.
        if exists(target) {
            let a = try? source.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
            let b = try? target.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
            guard let x = a as? NSObject, let y = b as? NSObject, x == y else { throw FileFailure.destinationExists }
        }
        try fm.moveItem(at: source, to: target)
        return (target, .move(from: target, to: source))
    }
    static func trash(_ source: URL) throws -> UndoStep? {
        var result: NSURL?
        try fm.trashItem(at: source, resultingItemURL: &result)
        return result.map { .move(from: $0 as URL, to: source) }
    }
    static func undo(_ step: UndoStep) throws {
        switch step.action {
        case .move(let from, let to):
            if from == to { return }
            guard exists(from) else { throw FileFailure.missingFile }
            guard step.identity.matches(from) else { throw FileFailure.changedSinceOperation }
            if exists(to) && !(from.path.lowercased() == to.path.lowercased() && step.identity.matches(to)) { throw FileFailure.destinationExists }
            try fm.moveItem(at: from, to: to)
        case .trash(let url):
            guard step.identity.matches(url) else { throw FileFailure.changedSinceOperation }
            _ = try trash(url)
        }
    }
    static func compress(_ urls: [URL], into folder: URL) throws -> (URL, UndoStep) {
        guard !urls.isEmpty, urls.allSatisfy({ exists($0) && $0.path != "/" }) else { throw FileFailure.missingFile }
        var common = urls[0].deletingLastPathComponent().standardizedFileURL
        for url in urls {
            while common.path != "/" && !(url.path.hasPrefix(common.path + "/")) { common.deleteLastPathComponent() }
        }
        let base = urls.count == 1 ? (FileEntry(urls[0]).navigable ? urls[0].lastPathComponent : urls[0].deletingPathExtension().lastPathComponent) : "归档"
        let target = uniqueURL(in: folder, name: base + ".zip")
        // Stage outside the source tree so a folder cannot archive its own growing output.
        let staging = fm.temporaryDirectory.appendingPathComponent("ExplorerMac-archive-\(UUID().uuidString)", isDirectory: true)
        let realStaging = staging.resolvingSymlinksInPath().path
        if urls.contains(where: { let e = FileEntry($0); return e.navigable && !e.isLink && realStaging.hasPrefix($0.resolvingSymlinksInPath().path + "/") }) { throw FileFailure.recursiveCopy }
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let temporary = staging.appendingPathComponent("archive.zip")
        let prefix = common.path == "/" ? "/" : common.path + "/"
        let relative = urls.map { String($0.standardizedFileURL.path.dropFirst(prefix.count)) }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); process.currentDirectoryURL = common
        process.arguments = ["-r", "-y", "-q", temporary.path, "--"] + relative
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        try process.run(); let output = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain: "ExplorerMac.Archive", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: String(data: output, encoding: .utf8) ?? "压缩未完成"]) }
        try fm.moveItem(at: temporary, to: target)
        return (target, .trash(target))
    }
}
