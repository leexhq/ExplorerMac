import SwiftUI
import AppKit

struct ExplorerView: View {
    @ObservedObject var model: ExplorerModel
    @State private var editingPath = false
    @State private var path = ""
    @FocusState private var addressFocused: Bool
    @FocusState private var searchFocused: Bool
    @State private var hoverSidebar: String?
    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            commandBar
            Divider()
            addressBar
            Divider()
            HSplitView {
                sidebar.frame(minWidth: 165, idealWidth: 200, maxWidth: 240)
                VStack(spacing: 0) {
                    if model.isSearching { HStack { Image(systemName: "magnifyingglass"); Text("“\(model.query)” 的搜索结果"); Spacer(); Text(model.recursive ? "含子文件夹" : "当前文件夹").foregroundStyle(.secondary) }.font(.system(size: 12)).padding(.horizontal, 20).padding(.vertical, 12).background(Color.accentColor.opacity(0.06)) }
                    ZStack {
                        FileBrowser(model: model)
                        if let error = model.directoryError {
                            VStack(spacing: 14) { Image(systemName: "folder.badge.questionmark").font(.system(size: 40)).foregroundStyle(.secondary); Text("无法读取此文件夹").font(.headline); Text(error).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440); Button("选择文件夹并授权访问…") { model.chooseFolder() }; Button("重试") { model.refresh() } }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .textBackgroundColor))
                        } else if model.entries.isEmpty && !model.loading {
                            VStack(spacing: 12) { Image(systemName: model.isSearching ? "magnifyingglass" : "folder").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(.tertiary); Text(model.isSearching ? "没有找到匹配的项目" : "此文件夹为空").foregroundStyle(.secondary); if !model.isSearching { Button("新建文件夹") { model.newFolder() }.buttonStyle(.borderless) } }.allowsHitTesting(!model.isSearching)
                        }
                        if model.loading { VStack { HStack { Spacer(); ProgressView().controlSize(.small).padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(12) }; Spacer() }.allowsHitTesting(false) }
                    }
                }.frame(minWidth: 360)
                if model.previewVisible { PreviewSidebar(model: model) }
            }
            Divider()
            statusBar
        }.background(Color(nsColor: .windowBackgroundColor)).frame(minWidth: 940, minHeight: 580)
            .onChange(of: model.addressFocusToken) { path = model.currentURL.path; editingPath = true; addressFocused = true }
            .onChange(of: model.searchFocusToken) { searchFocused = true }
            .onChange(of: model.currentURL) { editingPath = false; searchFocused = false; addressFocused = false }
    }
    var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(model.tabs) { tab in
                        HStack(spacing: 9) {
                            Image(systemName: "folder.fill").foregroundStyle(Color(red: 0.92, green: 0.68, blue: 0.22)).font(.system(size: 13))
                            Text(tab.url.path == "/" ? "Macintosh HD" : tab.url.lastPathComponent).font(.system(size: 12)).lineLimit(1)
                            Spacer(minLength: 4)
                            Button { model.closeTab(tab.id) } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.borderless).help("关闭标签页")
                        }.padding(.horizontal, 13).frame(width: 182, height: 35)
                            .background(tab.id == model.activeID ? Color(nsColor: .textBackgroundColor) : .clear, in: UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7))
                            .contentShape(Rectangle()).onTapGesture { model.activateTab(tab.id) }
                            .contextMenu { Button("新建标签页") { model.newTab(tab.url) }; Button("关闭标签页") { model.closeTab(tab.id) } }
                    }
                }.padding(.leading, 12).padding(.top, 7)
            }.fixedSize(horizontal: false, vertical: true)
            Button { model.newTab() } label: { Image(systemName: "plus").font(.system(size: 13)).frame(width: 36, height: 35) }.buttonStyle(.borderless).help("新建标签页 ⌘T")
            Spacer(minLength: 12)
            Text("EXPLORER").font(.system(size: 9, weight: .semibold, design: .rounded)).tracking(2).foregroundStyle(.tertiary).padding(.trailing, 20)
        }.frame(height: 43)
    }
    var commandBar: some View {
        HStack(spacing: 6) {
            Menu { Button("文件夹") { model.newFolder() }; Button("文本文档") { model.newTextFile() } } label: { Label("新建", systemImage: "plus.circle") }.menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 9).disabled(model.busy)
            separator
            tool("scissors", "剪切 ⌘X", enabled: !model.selection.isEmpty && !model.busy) { model.copy(cut: true) }
            tool("doc.on.doc", "复制 ⌘C", enabled: !model.selection.isEmpty && !model.busy) { model.copy() }
            tool("doc.on.clipboard", "粘贴 ⌘V", enabled: !model.busy) { model.paste() }
            tool("character.cursor.ibeam", "重命名 F2", enabled: model.selection.count == 1 && !model.busy) { model.rename() }
            tool("trash", "移到废纸篓 ⌘⌫", enabled: !model.selection.isEmpty && !model.busy) { model.deleteSelection() }
            separator
            Menu { Picker("排序依据", selection: $model.sortField) { ForEach(SortField.allCases, id: \.self) { Text($0.rawValue).tag($0) } }; Divider(); Toggle("升序", isOn: $model.ascending); Toggle("文件夹优先", isOn: $model.foldersFirst) } label: { Label("排序", systemImage: "arrow.up.arrow.down") }.menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 9)
            Menu { Picker("布局", selection: $model.viewMode) { ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }; Divider(); Toggle("显示隐藏文件", isOn: $model.showHidden); Toggle("文件扩展名", isOn: $model.showExtensions); Toggle("预览窗格", isOn: $model.previewVisible) } label: { Label("查看", systemImage: "square.grid.2x2") }.menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 9)
            separator
            tool("arrow.uturn.backward", "撤销\(model.undoLabel ?? "") ⌘Z", enabled: model.canUndo) { model.undo() }
            Menu { Button("打开文件夹…") { model.chooseFolder() }; Button("固定当前文件夹到快速访问") { model.pin(model.currentURL) }; Button("复制当前路径") { model.copyPaths() }; Button("在访达中显示") { model.reveal() }; Divider(); Button("属性") { model.properties() }; Button("键盘快捷键") { AppDelegate.showHelp() } } label: { Image(systemName: "ellipsis").frame(width: 24) }.menuStyle(.borderlessButton).fixedSize()
            Spacer(minLength: 5)
            Button { model.previewVisible.toggle() } label: { Label("预览", systemImage: "sidebar.right").font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 7).background(model.previewVisible ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 5)) }.buttonStyle(.plain).help("显示 / 隐藏预览窗格 ⌥⌘P")
        }.font(.system(size: 12)).padding(.horizontal, 14).frame(height: 54).background(Color(nsColor: .textBackgroundColor))
    }
    var separator: some View { Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1, height: 21).padding(.horizontal, 7) }
    func tool(_ icon: String, _ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View { Button(action: action) { Image(systemName: icon).font(.system(size: 15, weight: .regular)).frame(width: 34, height: 31) }.buttonStyle(.borderless).help(title).accessibilityLabel(title).disabled(!enabled) }
    var addressBar: some View {
        HStack(spacing: 8) {
            tool("arrow.left", "后退 ⌥←", enabled: model.canBack) { model.back() }
            tool("arrow.right", "前进 ⌥→", enabled: model.canForward) { model.forward() }
            tool("arrow.up", "上一级 ⌥↑", enabled: model.currentURL.path != "/") { model.up() }
            tool("arrow.clockwise", "刷新 F5 / ⌘R") { model.refresh() }
            HStack(spacing: 9) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                if editingPath {
                    TextField("输入文件夹路径", text: $path).textFieldStyle(.plain).focused($addressFocused).onSubmit { model.navigatePath(path); editingPath = false; model.selectionFocusToken += 1 }.onExitCommand { editingPath = false; model.selectionFocusToken += 1 }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { ForEach(breadcrumbs, id: \.path) { url in Button { model.navigate(url) } label: { Text(url.path == "/" ? "此电脑" : url.lastPathComponent).lineLimit(1) }.buttonStyle(.plain); Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary) } }
                    }
                    Button { path = model.currentURL.path; editingPath = true; addressFocused = true } label: { Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(.secondary) }.buttonStyle(.plain).help("编辑地址 ⌘L")
                }
            }.font(.system(size: 12)).padding(.horizontal, 12).frame(height: 34).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5))
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索 \(model.currentTitle)", text: $model.query).textFieldStyle(.plain).focused($searchFocused).onExitCommand { model.query = ""; searchFocused = false; model.selectionFocusToken += 1 }
                if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
                Menu { Toggle("包含子文件夹", isOn: $model.recursive) } label: { Image(systemName: "chevron.down").font(.system(size: 9)) }.menuStyle(.borderlessButton).frame(width: 17).help("搜索范围")
            }.font(.system(size: 12)).padding(.horizontal, 11).frame(width: 235, height: 34).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5))
        }.padding(.horizontal, 12).frame(height: 56)
    }
    var breadcrumbs: [URL] {
        var urls: [URL] = []; var url = model.currentURL
        while url.path != "/" && urls.count < 24 { urls.insert(url, at: 0); url.deleteLastPathComponent() }
        urls.insert(URL(fileURLWithPath: "/"), at: 0)
        return urls.count > 5 ? [urls[0]] + Array(urls.suffix(4)) : urls
    }
    var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                sideRow("主文件夹", icon: "house", url: FileManager.default.homeDirectoryForCurrentUser)
                sideRow("最近使用", icon: "clock", url: nil) { AppDelegate.shared.openRecent() }
                sideSection("快速访问")
                let home = FileManager.default.homeDirectoryForCurrentUser
                sideRow("桌面", icon: "desktopcomputer", url: home.appendingPathComponent("Desktop"))
                sideRow("下载", icon: "arrow.down.circle", url: home.appendingPathComponent("Downloads"))
                sideRow("文稿", icon: "doc.text", url: home.appendingPathComponent("Documents"))
                sideRow("图片", icon: "photo", url: home.appendingPathComponent("Pictures"))
                sideRow("音乐", icon: "music.note", url: home.appendingPathComponent("Music"))
                sideRow("影片", icon: "film", url: home.appendingPathComponent("Movies"))
                ForEach(model.bookmarks) { bookmark in sideRow(bookmark.url.lastPathComponent, icon: "pin", url: bookmark.url).contextMenu { Button("取消固定") { model.unpin(bookmark.path) }; Button("在新标签页打开") { model.newTab(bookmark.url) } } }
                sideSection("此电脑")
                sideRow("应用程序", icon: "square.grid.2x2", url: URL(fileURLWithPath: "/Applications"))
                ForEach(model.volumes, id: \.path) { url in FolderTreeNode(model: model, url: url, title: url.path == "/" ? "Macintosh HD" : url.lastPathComponent) }
                sideRow("废纸篓", icon: "trash", url: nil) { NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")) }
                Spacer(minLength: 22)
                Button { model.chooseFolder() } label: { Label("打开其他位置…", systemImage: "folder.badge.plus").font(.system(size: 11)).foregroundStyle(.secondary) }.buttonStyle(.plain).padding(.horizontal, 17).padding(.top, 5)
            }.padding(.horizontal, 8).padding(.vertical, 13)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
    func sideSection(_ title: String) -> some View { Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary).padding(.leading, 15).padding(.top, 24).padding(.bottom, 8) }
    func sideRow(_ name: String, icon: String, url: URL?, action: (() -> Void)? = nil) -> some View {
        let selected = url == model.currentURL
        return HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 2).fill(selected ? Color.accentColor : Color.clear).frame(width: 3, height: 17)
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(selected ? Color.accentColor : Color.secondary).frame(width: 19)
            Text(name).font(.system(size: 12)).lineLimit(1); Spacer(minLength: 0)
        }.padding(.trailing, 9).frame(height: 33).background(selected ? Color.accentColor.opacity(0.1) : hoverSidebar == name ? Color.primary.opacity(0.035) : Color.clear, in: RoundedRectangle(cornerRadius: 5)).contentShape(Rectangle())
            .onTapGesture { if let action { action() } else if let url { model.navigate(url) } }.onHover { hoverSidebar = $0 ? name : nil }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in guard let url else { return false }; return handleDrop(providers, to: url) }
            .accessibilityAddTraits(.isButton).help(url?.path ?? name)
    }
    func handleDrop(_ providers: [NSItemProvider], to folder: URL) -> Bool {
        guard !model.busy else { return false }
        let group = DispatchGroup(); let lock = NSLock(); var urls: [URL] = []
        for provider in providers { group.enter(); provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in defer { group.leave() }; let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }; if let url, url.isFileURL { lock.lock(); urls.append(url); lock.unlock() } } }
        group.notify(queue: .main) { if !urls.isEmpty { model.transfer(urls, into: folder, move: false) } }; return true
    }
    var statusBar: some View {
        HStack(spacing: 15) {
            Text("\(model.entries.count) 个项目")
            if !model.selection.isEmpty { Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1, height: 12); Text("已选择 \(model.selection.count) 项"); Text(ByteCountFormatter.string(fromByteCount: model.selectedEntries.reduce(0) { $0 + ($1.navigable ? 0 : $1.size) }, countStyle: .file)) }
            if model.busy { ProgressView().controlSize(.mini); Text(model.operationStatus).lineLimit(1) }
            else if !model.notice.isEmpty { Text(model.notice).lineLimit(1).truncationMode(.middle).help(model.notice) }
            Spacer(minLength: 8)
            if model.selection.isEmpty && !model.busy && model.notice.isEmpty { Text(model.freeSpace).foregroundStyle(.tertiary) }
            Button { model.viewMode = .details } label: { Image(systemName: "list.bullet").foregroundStyle(model.viewMode == .details ? Color.accentColor : .secondary) }.buttonStyle(.plain).help("详细信息")
            Button { model.viewMode = .large } label: { Image(systemName: "square.grid.2x2").foregroundStyle(model.viewMode != .details ? Color.accentColor : .secondary) }.buttonStyle(.plain).help("大图标")
        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 19).frame(height: 33).background(Color(nsColor: .textBackgroundColor))
    }
}
