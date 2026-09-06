import AppKit
import Combine
import Darwin

struct ExplorerTab: Identifiable {
    let id = UUID()
    var history: [URL]
    var position = 0
    var url: URL { history[position] }
}
enum ViewMode: String, CaseIterable { case details = "详细信息", small = "中等图标", large = "大图标", huge = "超大图标" }
enum SortField: String, CaseIterable { case name = "名称", modified = "修改日期", kind = "类型", size = "大小" }
struct Bookmark: Identifiable { var id: String { path }; let path: String; var url: URL { URL(fileURLWithPath: path) } }
struct UndoBatch { let label: String; var steps: [UndoStep] }
final class ScanCancellation {
    private let lock = NSLock(); private var flag = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func cancel() { lock.lock(); flag = true; lock.unlock() }
}

final class ExplorerModel: ObservableObject {
    @Published var tabs: [ExplorerTab] = []
    @Published var activeID = UUID()
    @Published var entries: [FileEntry] = []
    @Published var selection: Set<URL> = []
    @Published var query = "" { didSet { scheduleSearch() } }
    @Published var recursive = false { didSet { refresh() } }
    @Published var showHidden = false { didSet { defaults.set(showHidden, forKey: "hidden"); refresh() } }
    @Published var showExtensions = true { didSet { defaults.set(showExtensions, forKey: "extensions") } }
    @Published var previewVisible = true { didSet { defaults.set(previewVisible, forKey: "preview") } }
    @Published var viewMode: ViewMode = .large { didSet { defaults.set(viewMode.rawValue, forKey: "view") } }
    @Published var sortField: SortField = .name { didSet { sortEntries() } }
    @Published var ascending = true { didSet { sortEntries() } }
    @Published var foldersFirst = true { didSet { sortEntries() } }
    @Published var loading = false
    @Published var busy = false
    @Published var operationStatus = ""
    @Published var notice = ""
    @Published var directoryError: String?
    @Published var bookmarks: [Bookmark] = []
    @Published var volumes: [URL] = []
    @Published var undoLabel: String?
    @Published var clipboardCut: Set<URL> = []
    @Published var addressFocusToken = 0
    @Published var searchFocusToken = 0
    @Published var selectionFocusToken = 0
    let defaults = UserDefaults.standard
    private var generation = UUID()
    private var searchJob: DispatchWorkItem?
    private var watcher: DispatchSourceFileSystemObject?
    private var watchRefresh: DispatchWorkItem?
    private var scanJob: DispatchWorkItem?
    private var scanCancellation = ScanCancellation()
    private var undoStack: [UndoBatch] = []
    private var cutChangeCount = -1
    private let operationQueue = DispatchQueue(label: "ExplorerMac.fileOperations", qos: .userInitiated)
    private var observers: [NSObjectProtocol] = []
    var activeIndex: Int { tabs.firstIndex(where: { $0.id == activeID }) ?? 0 }
    var currentURL: URL { tabs.isEmpty ? FileManager.default.homeDirectoryForCurrentUser : tabs[activeIndex].url }
    var currentTitle: String { currentURL.path == "/" ? "Macintosh HD" : currentURL.lastPathComponent }
    var selectedEntries: [FileEntry] { entries.filter { selection.contains($0.url) } }
    var canBack: Bool { !tabs.isEmpty && tabs[activeIndex].position > 0 }
    var canForward: Bool { !tabs.isEmpty && tabs[activeIndex].position < tabs[activeIndex].history.count - 1 }
    var canUndo: Bool { !undoStack.isEmpty && !busy }
    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var freeSpace: String {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: currentURL.path)
        guard let n = attrs?[.systemFreeSize] as? NSNumber else { return "" }
        return ByteCountFormatter.string(fromByteCount: n.int64Value, countStyle: .file) + " 可用"
    }
    init(startURL: URL? = nil) {
        showHidden = defaults.bool(forKey: "hidden")
        showExtensions = defaults.object(forKey: "extensions") as? Bool ?? true
        previewVisible = defaults.object(forKey: "preview") as? Bool ?? true
        viewMode = ViewMode(rawValue: defaults.string(forKey: "view") ?? "") ?? .large
        bookmarks = (defaults.stringArray(forKey: "bookmarks") ?? []).map { Bookmark(path: $0) }
        let saved = (defaults.stringArray(forKey: "tabs") ?? []).prefix(12).map { URL(fileURLWithPath: $0) }.filter { FileCore.exists($0) && FileEntry($0).navigable }
        tabs = (startURL.map { [$0] } ?? (saved.isEmpty ? [FileManager.default.homeDirectoryForCurrentUser] : Array(saved))).map { ExplorerTab(history: [$0]) }
        activeID = tabs.first!.id
        reloadVolumes()
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.reloadVolumes() })
        }
        refresh(); watchDirectory()
    }
    deinit { watcher?.cancel(); scanJob?.cancel(); scanCancellation.cancel(); for o in observers { NSWorkspace.shared.notificationCenter.removeObserver(o) } }
    func reloadVolumes() { volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? [] }
    func displayName(_ entry: FileEntry) -> String { showExtensions || entry.navigable ? entry.name : entry.url.deletingPathExtension().lastPathComponent }
    func saveTabs() { defaults.set(tabs.map { $0.url.path }, forKey: "tabs") }
    func navigate(_ url: URL) {
        let target = url.standardizedFileURL
        guard FileEntry(target).navigable else { openURL(target); return }
        if target != currentURL {
            var t = tabs[activeIndex]
            t.history = Array(t.history.prefix(t.position + 1)); t.history.append(target); t.position += 1
            tabs[activeIndex] = t
        }
        NSDocumentController.shared.noteNewRecentDocumentURL(target)
        directoryChanged()
    }
    func directoryChanged() { query = ""; selection = []; entries = []; notice = ""; refresh(); watchDirectory(); saveTabs() }
    func back() { guard canBack else { return }; tabs[activeIndex].position -= 1; directoryChanged() }
    func forward() { guard canForward else { return }; tabs[activeIndex].position += 1; directoryChanged() }
    func up() { navigate(currentURL.deletingLastPathComponent()) }
    func newTab(_ url: URL? = nil) { let t = ExplorerTab(history: [url ?? currentURL]); tabs.append(t); activeID = t.id; directoryChanged() }
    func activateTab(_ id: UUID) { guard activeID != id else { return }; activeID = id; directoryChanged() }
    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { NSApp.keyWindow?.close(); return }
        let index = tabs.firstIndex(where: { $0.id == id }) ?? 0
        tabs.removeAll { $0.id == id }
        if activeID == id { activeID = tabs[min(index, tabs.count - 1)].id; directoryChanged() }; saveTabs()
    }
    func nextTab(_ offset: Int) { activateTab(tabs[(activeIndex + offset + tabs.count) % tabs.count].id) }
    func navigatePath(_ path: String) {
        let s = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let target: URL
        if s.hasPrefix("file://"), let url = URL(string: s), url.isFileURL { target = url }
        else { let expanded = (s as NSString).expandingTildeInPath; target = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : currentURL.appendingPathComponent(expanded) }
        guard FileCore.exists(target) else { showError("无法打开路径", FileFailure.missingFile); return }
        navigate(target)
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.directoryURL = currentURL
        panel.prompt = "打开文件夹"
        if panel.runModal() == .OK, let url = panel.url { navigate(url) }
    }
    func scheduleSearch() { searchJob?.cancel(); let job = DispatchWorkItem { [weak self] in self?.refresh() }; searchJob = job; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: job) }
    func refresh() {
        searchJob?.cancel(); scanJob?.cancel(); scanCancellation.cancel()
        let cancellation = ScanCancellation(); scanCancellation = cancellation
        let token = UUID(); generation = token
        let folder = currentURL, hidden = showHidden, term = query.trimmingCharacters(in: .whitespacesAndNewlines), deep = recursive && isSearching
        loading = true; directoryError = nil
        let job = DispatchWorkItem { [weak self] in
            var result: [FileEntry] = []; var issue: String?; var limited = false; var skipped = 0
            do {
                let options: FileManager.DirectoryEnumerationOptions = hidden ? [] : [.skipsHiddenFiles]
                if deep {
                    // Check the root explicitly; enumerator otherwise silently returns an empty result on access errors.
                    _ = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: options)
                    let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(FileEntry.keys), options: options.union(.skipsPackageDescendants), errorHandler: { _, _ in skipped += 1; return true })
                    var scanned = 0
                    while let url = enumerator?.nextObject() as? URL {
                        if cancellation.cancelled { return }
                        scanned += 1
                        if url.lastPathComponent.localizedStandardContains(term) { result.append(FileEntry(url)) }
                        if scanned >= 200_000 || result.count >= 20_000 { limited = true; break }
                    }
                } else {
                    result = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(FileEntry.keys), options: options).compactMap { url in
                        if cancellation.cancelled { return nil }
                        return term.isEmpty || url.lastPathComponent.localizedStandardContains(term) ? FileEntry(url) : nil
                    }
                }
            } catch { issue = error.localizedDescription }
            if cancellation.cancelled { return }
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.entries = result; self.sortEntries(); self.selection.formIntersection(Set(result.map(\.url)))
                self.loading = false; self.directoryError = issue
                if limited { self.notice = "结果已截断（最多扫描 200,000 项 / 显示 20,000 个匹配项），请缩小搜索范围。" }
                else if skipped > 0 { self.notice = "搜索跳过了 \(skipped) 个无法读取的位置。" }
            }
        }
        scanJob = job; DispatchQueue.global(qos: .userInitiated).async(execute: job)
    }
    func sortEntries() {
        entries.sort { a, b in
            if foldersFirst && a.navigable != b.navigable { return a.navigable }
            let comparison: ComparisonResult
            switch sortField {
            case .name: comparison = a.name.localizedStandardCompare(b.name)
            case .kind: comparison = a.kind.localizedStandardCompare(b.kind)
            case .size: comparison = a.size == b.size ? .orderedSame : (a.size < b.size ? .orderedAscending : .orderedDescending)
            case .modified: comparison = a.modified.compare(b.modified)
            }
            let r = comparison == .orderedSame ? a.url.path.localizedStandardCompare(b.url.path) : comparison
            return ascending ? r == .orderedAscending : r == .orderedDescending
        }
    }
    func watchDirectory() {
        watcher?.cancel(); watcher = nil; watchRefresh?.cancel()
        let fd = Darwin.open(currentURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .attrib, .extend], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.watchRefresh?.cancel()
            let job = DispatchWorkItem { [weak self] in self?.refresh() }
            self.watchRefresh = job; DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: job)
        }
        source.setCancelHandler { Darwin.close(fd) }; watcher = source; source.resume()
    }
    func openURL(_ url: URL) { if FileEntry(url).navigable { navigate(url) } else if !NSWorkspace.shared.open(url) { showError("无法打开文件", FileFailure.missingFile) } else { NSDocumentController.shared.noteNewRecentDocumentURL(url) } }
    func openSelection() { for entry in selectedEntries.prefix(10) { openURL(entry.url) } }
    func quickLook() { guard !selectedEntries.isEmpty else { return }; PreviewController.shared.show(entries: selectedEntries.count > 1 || selectedEntries.first!.navigable ? selectedEntries : entries.filter { !$0.navigable }, selected: selectedEntries.first!.url) }
    func reveal() { NSWorkspace.shared.activateFileViewerSelecting(selection.isEmpty ? [currentURL] : selectedEntries.map(\.url)) }
    func pin(_ url: URL? = nil) {
        let target = url ?? selectedEntries.first(where: \.navigable)?.url ?? currentURL
        if !bookmarks.contains(where: { $0.path == target.path }) { bookmarks.append(Bookmark(path: target.path)); defaults.set(bookmarks.map(\.path), forKey: "bookmarks") }
    }
    func unpin(_ path: String) { bookmarks.removeAll { $0.path == path }; defaults.set(bookmarks.map(\.path), forKey: "bookmarks") }
    func copyPaths() { let text = (selection.isEmpty ? [currentURL] : selectedEntries.map(\.url)).map(\.path).joined(separator: "\n"); NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    func copy(cut: Bool = false) {
        guard !selection.isEmpty, !busy else { return }
        let urls = selectedEntries.map(\.url)
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(urls as [NSURL])
        clipboardCut = cut ? Set(urls) : []; cutChangeCount = cut ? NSPasteboard.general.changeCount : -1
        notice = "已\(cut ? "剪切" : "复制") \(urls.count) 项，在目标文件夹粘贴。"
    }
    func paste() {
        guard !busy, let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return }
        let move = cutChangeCount == NSPasteboard.general.changeCount && !clipboardCut.isEmpty
        transfer(urls, into: currentURL, move: move)
        if move { clipboardCut = []; cutChangeCount = -1 }
    }
    func transfer(_ urls: [URL], into folder: URL, move: Bool) {
        guard !busy else { return }
        perform(label: move ? "移动" : "复制", count: urls.count) { progress in
            var steps: [UndoStep] = [], errors: [String] = []
            for (i, url) in urls.enumerated() {
                progress(i + 1, url.lastPathComponent)
                do { let (_, undo) = try FileCore.transfer(url, into: folder, move: move); steps.append(undo) }
                catch { errors.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
            }
            return (steps, errors)
        }
    }
    func pickTransfer(move: Bool) {
        let urls = selectedEntries.map(\.url); guard !urls.isEmpty, !busy else { return }
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true; p.prompt = move ? "移动到此处" : "复制到此处"
        if p.runModal() == .OK, let folder = p.url { transfer(urls, into: folder, move: move) }
    }
    func namePrompt(title: String, value: String) -> String? {
        let alert = NSAlert(); alert.messageText = title; alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
        let input = NSTextField(string: value); input.frame = NSRect(x: 0, y: 0, width: 360, height: 26); alert.accessoryView = input
        alert.window.initialFirstResponder = input
        return alert.runModal() == .alertFirstButtonReturn ? input.stringValue : nil
    }
    func newFolder() {
        guard !busy, let name = namePrompt(title: "新建文件夹", value: "新建文件夹") else { return }
        let folder = currentURL
        perform(label: "新建文件夹", count: 1) { _ in
            do { try FileCore.validateName(name); let url = FileCore.uniqueURL(in: folder, name: name); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false); return ([.trash(url)], []) }
            catch { return ([], [error.localizedDescription]) }
        }
    }
    func newTextFile() {
        guard !busy, let name = namePrompt(title: "新建文本文件", value: "新建文本文档.txt") else { return }
        let folder = currentURL
        perform(label: "新建文本文件", count: 1) { _ in
            do { try FileCore.validateName(name); let url = FileCore.uniqueURL(in: folder, name: name); try Data().write(to: url, options: .withoutOverwriting); return ([.trash(url)], []) }
            catch { return ([], [error.localizedDescription]) }
        }
    }
    func rename() {
        guard !busy, selectedEntries.count == 1, let entry = selectedEntries.first, let name = namePrompt(title: "重命名", value: entry.name), name != entry.name else { return }
        perform(label: "重命名", count: 1) { _ in do { let (_, step) = try FileCore.rename(entry.url, name: name); return ([step], []) } catch { return ([], [error.localizedDescription]) } }
    }
    func compressSelection() {
        let urls = selectedEntries.map(\.url), folder = currentURL
        guard !busy, !urls.isEmpty else { return }
        perform(label: "压缩为 ZIP", count: urls.count) { _ in
            do { let (_, step) = try FileCore.compress(urls, into: folder); return ([step], []) }
            catch { return ([], [error.localizedDescription]) }
        }
    }
    func deleteSelection() {
        let urls = selectedEntries.map(\.url); guard !urls.isEmpty, !busy else { return }
        let alert = NSAlert(); alert.messageText = "将 \(urls.count) 个项目移到废纸篓？"; alert.informativeText = "可在废纸篓中恢复。"; alert.addButton(withTitle: "移到废纸篓"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform(label: "移到废纸篓", count: urls.count) { progress in
            var steps: [UndoStep] = [], errors: [String] = []
            for (i, url) in urls.enumerated() { progress(i + 1, url.lastPathComponent); do { if let step = try FileCore.trash(url) { steps.append(step) } } catch { errors.append("\(url.lastPathComponent)：\(error.localizedDescription)") } }
            return (steps, errors)
        }
    }
    func perform(label: String, count: Int, work: @escaping (@escaping (Int, String) -> Void) -> ([UndoStep], [String])) {
        guard !busy else { return }; busy = true; operationStatus = label + "…"
        operationQueue.async {
            let (steps, errors) = work { i, name in DispatchQueue.main.async { self.operationStatus = "\(label) \(i)/\(count) · \(name)" } }
            DispatchQueue.main.async {
                if !steps.isEmpty { self.undoStack.append(UndoBatch(label: label, steps: steps)); if self.undoStack.count > 30 { self.undoStack.removeFirst() } }
                self.undoLabel = self.undoStack.last?.label; self.busy = false; self.operationStatus = ""
                self.notice = errors.isEmpty ? "\(label)完成" : "\(label)：\(errors.count) 项未完成"
                self.refresh()
                if !errors.isEmpty { self.showMessage("部分操作未完成", errors.prefix(8).joined(separator: "\n")) }
            }
        }
    }
    func undo() {
        guard !busy, let batch = undoStack.popLast() else { return }
        busy = true; operationStatus = "正在撤销\(batch.label)…"
        operationQueue.async {
            var remaining: [UndoStep] = []; var errors: [String] = []
            for step in batch.steps.reversed() { do { try FileCore.undo(step) } catch { remaining.append(step); errors.append(error.localizedDescription) } }
            DispatchQueue.main.async {
                if !remaining.isEmpty { self.undoStack.append(UndoBatch(label: batch.label, steps: remaining.reversed())) }
                self.undoLabel = self.undoStack.last?.label; self.busy = false; self.operationStatus = ""; self.notice = "已撤销\(batch.label)"; self.refresh()
                if !errors.isEmpty { self.showMessage("部分撤销未完成", errors.prefix(8).joined(separator: "\n")) }
            }
        }
    }
    func showError(_ title: String, _ error: Error) { showMessage(title, error.localizedDescription) }
    func showMessage(_ title: String, _ text: String) { let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal() }
    func properties() {
        let items = selectedEntries.isEmpty ? [FileEntry(currentURL)] : selectedEntries
        let total = items.reduce(Int64(0)) { $0 + ($1.navigable ? 0 : $1.size) }
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        if items.count == 1, let e = items.first {
            let attrs = try? FileManager.default.attributesOfItem(atPath: e.url.path)
            let perms = (attrs?[.posixPermissions] as? NSNumber).map { String(format: "%03o", $0.intValue) } ?? "—"
            showMessage(e.name, "类型：\(e.kind)\n位置：\(e.url.path)\n大小：\(e.navigable ? "文件夹（未递归计算）" : e.sizeText)\n修改：\(df.string(from: e.modified))\n创建：\(df.string(from: e.created))\n权限：\(perms)\n\(e.isLink ? "这是一个符号链接。" : "")")
        } else { showMessage("\(items.count) 个项目", "文件大小合计：\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))\n文件夹：\(items.filter(\.navigable).count) 个\n（不包含文件夹内的内容）") }
    }
}
