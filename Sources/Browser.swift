import AppKit
import SwiftUI
import QuickLookThumbnailing
import ImageIO

final class ThumbnailStore {
    static let shared = ThumbnailStore()
    private let cache = NSCache<NSString, NSImage>()
    private var pending: [String: [(NSImage) -> Void]] = [:]
    private let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 4; q.qualityOfService = .userInitiated; return q }()
    init() { cache.totalCostLimit = 160 * 1024 * 1024; cache.countLimit = 700 }
    func load(_ entry: FileEntry, pixels: Int = 400, completion: @escaping (NSImage) -> Void) {
        let key = "\(entry.url.path)|\(entry.modified.timeIntervalSince1970)|\(pixels)"
        if let image = cache.object(forKey: key as NSString) { completion(image); return }
        if pending[key] != nil { pending[key]?.append(completion); return }
        if entry.navigable { completion(FileArtwork.icon(entry)); return }
        pending[key] = [completion]
        let fallback = FileArtwork.icon(entry)
        queue.addOperation {
            if entry.isImage, let source = CGImageSourceCreateWithURL(entry.url as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
                let image = NSImage(cgImage: cg, size: .zero)
                DispatchQueue.main.async { self.finish(key, image, cost: cg.width * cg.height * 4) }
            } else {
                let request = QLThumbnailGenerator.Request(fileAt: entry.url, size: CGSize(width: pixels, height: pixels), scale: 1, representationTypes: .all)
                // Quick Look manages provider work asynchronously. Requests are coalesced above.
                QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                    DispatchQueue.main.async { self.finish(key, thumbnail?.nsImage ?? fallback, cost: pixels * pixels * 4) }
                }
            }
        }
    }
    private func finish(_ key: String, _ image: NSImage, cost: Int) {
        cache.setObject(image, forKey: key as NSString, cost: cost)
        let callbacks = pending.removeValue(forKey: key) ?? []; for c in callbacks { c(image) }
    }
}

final class MenuClosure: NSObject {
    let closure: () -> Void
    init(_ closure: @escaping () -> Void) { self.closure = closure }
    @objc func run(_ sender: Any?) { closure() }
}
extension NSMenu {
    func action(_ title: String, symbol: String? = nil, enabled: Bool = true, _ closure: @escaping () -> Void) {
        let target = MenuClosure(closure); let item = NSMenuItem(title: title, action: #selector(MenuClosure.run(_:)), keyEquivalent: "")
        item.target = target; item.representedObject = target; item.isEnabled = enabled
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) }
        addItem(item)
    }
}
extension ExplorerModel {
    func contextMenu() -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        if !selection.isEmpty {
            menu.action("打开", symbol: "arrow.up.forward.square") { self.openSelection() }
            if selectedEntries.count == 1, let e = selectedEntries.first, e.navigable { menu.action("在新标签页中打开", symbol: "plus.square.on.square") { self.newTab(e.url) }; menu.action("固定到快速访问", symbol: "pin") { self.pin(e.url) } }
            menu.action("快速预览                 Space", symbol: "eye") { self.quickLook() }
            menu.addItem(.separator())
            menu.action("剪切                              ⌘X", symbol: "scissors", enabled: !busy) { self.copy(cut: true) }
            menu.action("复制                              ⌘C", symbol: "doc.on.doc", enabled: !busy) { self.copy() }
            menu.action("复制到…", symbol: "folder.badge.plus", enabled: !busy) { self.pickTransfer(move: false) }
            menu.action("移动到…", symbol: "folder", enabled: !busy) { self.pickTransfer(move: true) }
            menu.action("重命名                           F2", symbol: "pencil", enabled: selection.count == 1 && !busy) { self.rename() }
            menu.action("移到废纸篓", symbol: "trash", enabled: !busy) { self.deleteSelection() }
            menu.action("压缩为 ZIP", symbol: "archivebox", enabled: !busy) { self.compressSelection() }
            menu.addItem(.separator())
        }
        menu.action("粘贴                              ⌘V", symbol: "doc.on.clipboard", enabled: !busy) { self.paste() }
        menu.action("新建文件夹", symbol: "folder.badge.plus", enabled: !busy) { self.newFolder() }
        menu.action("新建文本文件", symbol: "doc.badge.plus", enabled: !busy) { self.newTextFile() }
        menu.addItem(.separator())
        menu.action("复制路径", symbol: "link") { self.copyPaths() }
        menu.action("在访达中显示", symbol: "macwindow") { self.reveal() }
        menu.action("属性                              ⌘I", symbol: "info.circle") { self.properties() }
        return menu
    }
    func browserKey(_ event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            switch event.keyCode {
            case 36, 76: openSelection(); return true
            case 49: quickLook(); return true
            case 51: back(); return true
            case 117: deleteSelection(); return true
            case 120: rename(); return true
            case 96: refresh(); return true
            default: break
            }
        }
        if event.modifierFlags.contains(.option) {
            switch event.keyCode { case 123: back(); return true; case 124: forward(); return true; case 126: up(); return true; default: break }
        }
        return false
    }
}

final class TileView: NSView {
    var selected = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if selected {
            NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
            let rect = bounds.insetBy(dx: 3, dy: 2)
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            NSColor.controlAccentColor.withAlphaComponent(0.5).setStroke()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6).stroke()
        }
    }
}
final class FileTile: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("fileTile")
    let thumbnail = NSImageView()
    let label = NSTextField(wrappingLabelWithString: "")
    let subtitle = NSTextField(labelWithString: "")
    var representedURL: URL?
    override func loadView() {
        view = TileView(); view.wantsLayer = true
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        label.alignment = .center; label.maximumNumberOfLines = 2; label.lineBreakMode = .byTruncatingMiddle; label.font = .systemFont(ofSize: 12)
        subtitle.alignment = .center; subtitle.font = .systemFont(ofSize: 10); subtitle.textColor = .secondaryLabelColor; subtitle.lineBreakMode = .byTruncatingTail
        for v in [thumbnail, label, subtitle] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        // AppKit uses these outlets to construct the native drag image.
        imageView = thumbnail; textField = label
        NSLayoutConstraint.activate([
            thumbnail.topAnchor.constraint(equalTo: view.topAnchor, constant: 12), thumbnail.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14), thumbnail.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14), thumbnail.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -57),
            label.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 7), label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 7), label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -7), label.heightAnchor.constraint(equalToConstant: 31),
            subtitle.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 1), subtitle.leadingAnchor.constraint(equalTo: label.leadingAnchor), subtitle.trailingAnchor.constraint(equalTo: label.trailingAnchor)
        ])
    }
    override var isSelected: Bool { didSet { (view as? TileView)?.selected = isSelected } }
    func configure(_ entry: FileEntry, model: ExplorerModel) {
        representedURL = entry.url; label.stringValue = model.displayName(entry); subtitle.stringValue = entry.navigable ? "文件夹" : entry.sizeText
        thumbnail.image = FileArtwork.icon(entry)
        view.alphaValue = model.clipboardCut.contains(entry.url) ? 0.45 : 1
        view.toolTip = entry.url.path
        view.setAccessibilityElement(true); view.setAccessibilityLabel(entry.name); view.setAccessibilityRole(.button)
        ThumbnailStore.shared.load(entry) { [weak self] image in guard self?.representedURL == entry.url else { return }; self?.thumbnail.image = image }
    }
    override func prepareForReuse() { super.prepareForReuse(); representedURL = nil; thumbnail.image = nil }
}

final class ExplorerCollection: NSCollectionView {
    weak var model: ExplorerModel?
    override func keyDown(with event: NSEvent) { if model?.browserKey(event) != true { super.keyDown(with: event) } }
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2, let index = indexPathForItem(at: convert(event.locationInWindow, from: nil)), let model, index.item < model.entries.count { model.openURL(model.entries[index.item].url) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model else { return nil }
        if let index = indexPathForItem(at: convert(event.locationInWindow, from: nil)), index.item < model.entries.count {
            let url = model.entries[index.item].url
            if !model.selection.contains(url) { selectionIndexPaths = [index]; model.selection = [url] }
        } else { selectionIndexPaths = []; model.selection = [] }
        return model.contextMenu()
    }
}
final class ExplorerTable: NSTableView {
    weak var model: ExplorerModel?
    override func keyDown(with event: NSEvent) { if model?.browserKey(event) != true { super.keyDown(with: event) } }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model else { return nil }
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 && row < model.entries.count {
            if !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); model.selection = [model.entries[row].url] }
        } else { deselectAll(nil); model.selection = [] }
        return model.contextMenu()
    }
}

struct FileBrowser: NSViewRepresentable {
    @ObservedObject var model: ExplorerModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> NSView { context.coordinator.setup(); return context.coordinator.host }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.update() }
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSTableViewDataSource, NSTableViewDelegate {
        let model: ExplorerModel
        let host = NSView(), gridScroll = NSScrollView(), tableScroll = NSScrollView()
        let grid = ExplorerCollection(), table = ExplorerTable(), layout = NSCollectionViewFlowLayout()
        var lastEntries: [FileEntry] = [], lastMode: ViewMode?, lastExtensions = true, lastCut: Set<URL> = []
        var updating = false, lastFocus = -1
        init(_ model: ExplorerModel) { self.model = model }
        func setup() {
            grid.model = model; grid.dataSource = self; grid.delegate = self; grid.collectionViewLayout = layout
            grid.isSelectable = true; grid.allowsMultipleSelection = true; grid.allowsEmptySelection = true
            grid.backgroundColors = [.textBackgroundColor]; grid.register(FileTile.self, forItemWithIdentifier: FileTile.identifier)
            layout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16); layout.minimumInteritemSpacing = 8; layout.minimumLineSpacing = 8
            gridScroll.documentView = grid; gridScroll.hasVerticalScroller = true; gridScroll.autohidesScrollers = true
            table.model = model; table.dataSource = self; table.delegate = self; table.allowsMultipleSelection = true; table.allowsEmptySelection = true; table.rowHeight = 34; table.style = .plain
            table.usesAlternatingRowBackgroundColors = true; table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
            let specs: [(String, String, CGFloat)] = [("name", "名称", 290), ("modified", "修改日期", 155), ("kind", "类型", 135), ("size", "大小", 95), ("location", "所在位置", 240)]
            for (key, title, width) in specs { let column = NSTableColumn(identifier: .init(key)); column.title = title; column.width = width; column.minWidth = 65; column.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: true); table.addTableColumn(column) }
            table.target = self; table.doubleAction = #selector(doubleClick)
            tableScroll.documentView = table; tableScroll.hasVerticalScroller = true; tableScroll.hasHorizontalScroller = true; tableScroll.autohidesScrollers = true
            for scroll in [gridScroll, tableScroll] { scroll.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(scroll); NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: host.topAnchor), scroll.bottomAnchor.constraint(equalTo: host.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: host.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: host.trailingAnchor)]) }
            grid.registerForDraggedTypes([.fileURL]); table.registerForDraggedTypes([.fileURL]); grid.setDraggingSourceOperationMask(.copy, forLocal: false); grid.setDraggingSourceOperationMask(.copy, forLocal: true); table.setDraggingSourceOperationMask(.copy, forLocal: false); table.setDraggingSourceOperationMask(.copy, forLocal: true)
        }
        func update() {
            updating = true; defer { updating = false }
            let changed = lastEntries != model.entries || lastExtensions != model.showExtensions || lastCut != model.clipboardCut
            let modeChanged = lastMode != model.viewMode
            if modeChanged {
                gridScroll.isHidden = model.viewMode == .details; tableScroll.isHidden = model.viewMode != .details
                let width: CGFloat = model.viewMode == .small ? 104 : model.viewMode == .huge ? 220 : 148
                layout.itemSize = NSSize(width: width, height: width + 45); layout.invalidateLayout(); lastMode = model.viewMode
            }
            table.tableColumns.last?.isHidden = !(model.isSearching && model.recursive)
            if changed {
                lastEntries = model.entries; lastExtensions = model.showExtensions; lastCut = model.clipboardCut
                grid.reloadData(); table.reloadData()
            }
            let indexes = model.entries.enumerated().filter { model.selection.contains($0.element.url) }.map(\.offset)
            let paths = Set(indexes.map { IndexPath(item: $0, section: 0) })
            if grid.selectionIndexPaths != paths { grid.selectionIndexPaths = paths }
            let rows = IndexSet(indexes); if table.selectedRowIndexes != rows { table.selectRowIndexes(rows, byExtendingSelection: false) }
            if modeChanged || lastFocus != model.selectionFocusToken { lastFocus = model.selectionFocusToken; DispatchQueue.main.async { self.host.window?.makeFirstResponder(self.model.viewMode == .details ? self.table : self.grid) } }
        }
        @objc func doubleClick() { let row = table.clickedRow; if row >= 0 && row < model.entries.count { model.openURL(model.entries[row].url) } }
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { model.entries.count }
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem { let item = collectionView.makeItem(withIdentifier: FileTile.identifier, for: indexPath) as! FileTile; item.configure(model.entries[indexPath.item], model: model); return item }
        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { syncGridSelection() }
        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { syncGridSelection() }
        func syncGridSelection() { guard !updating else { return }; model.selection = Set(grid.selectionIndexPaths.compactMap { $0.item < model.entries.count ? model.entries[$0.item].url : nil }) }
        func numberOfRows(in tableView: NSTableView) -> Int { model.entries.count }
        func tableViewSelectionDidChange(_ notification: Notification) { guard !updating else { return }; model.selection = Set(table.selectedRowIndexes.compactMap { $0 < model.entries.count ? model.entries[$0].url : nil }) }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < model.entries.count, let key = tableColumn?.identifier.rawValue else { return nil }
            let e = model.entries[row]
            if key == "name" {
                let cell = NSTableCellView(); let icon = NSImageView(); icon.image = FileArtwork.icon(e); icon.imageScaling = .scaleProportionallyDown
                let label = NSTextField(labelWithString: model.displayName(e)); label.font = .systemFont(ofSize: 12); label.lineBreakMode = .byTruncatingMiddle
                for v in [icon, label] { v.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(v) }
                NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 7), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 22), icon.heightAnchor.constraint(equalToConstant: 22), label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
                cell.imageView = icon; cell.textField = label; cell.toolTip = e.url.path; cell.alphaValue = model.clipboardCut.contains(e.url) ? 0.45 : 1
                return cell
            }
            let text: String
            switch key { case "size": text = e.sizeText; case "modified": text = Self.dateFormatter.string(from: e.modified); case "kind": text = e.kind; default: text = e.url.deletingLastPathComponent().path }
            let cell = NSTableCellView(); let label = NSTextField(labelWithString: text); label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor; label.lineBreakMode = .byTruncatingMiddle; label.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(label); cell.textField = label
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -7), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            if key == "size" { label.alignment = .right }; return cell
        }
        static let dateFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd HH:mm"; return f }()
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let d = tableView.sortDescriptors.first else { return }
            switch d.key { case "name": model.sortField = .name; case "modified": model.sortField = .modified; case "kind": model.sortField = .kind; case "size": model.sortField = .size; default: return }; model.ascending = d.ascending
        }
        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? { model.entries[indexPath.item].url as NSURL }
        func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool { !model.busy && !indexPaths.isEmpty }
        func collectionView(_ collectionView: NSCollectionView, updateDraggingItemsForDrag draggingInfo: NSDraggingInfo) { draggingInfo.animatesToDestination = true }
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? { model.entries[row].url as NSURL }
        func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
            guard !model.busy else { return [] }
            let point = collectionView.convert(draggingInfo.draggingLocation, from: nil)
            if let hit = collectionView.indexPathForItem(at: point), hit.item < model.entries.count && model.entries[hit.item].navigable { proposedDropIndexPath.pointee = hit as NSIndexPath; proposedDropOperation.pointee = .on }
            else { proposedDropOperation.pointee = .before }
            return .copy
        }
        func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
            let folder = dropOperation == .on && indexPath.item < model.entries.count && model.entries[indexPath.item].navigable ? model.entries[indexPath.item].url : model.currentURL
            return accept(draggingInfo, folder)
        }
        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            guard !model.busy else { return [] }
            if row >= 0 && row < model.entries.count && model.entries[row].navigable { tableView.setDropRow(row, dropOperation: .on) }
            else { tableView.setDropRow(-1, dropOperation: .on) }; return .copy
        }
        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool { accept(info, row >= 0 && row < model.entries.count && model.entries[row].navigable ? model.entries[row].url : model.currentURL) }
        func accept(_ info: NSDraggingInfo, _ folder: URL) -> Bool { guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }; model.transfer(urls, into: folder, move: false); return true }
    }
}
