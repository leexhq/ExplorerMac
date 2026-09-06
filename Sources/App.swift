import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let shared = AppDelegate()
    var windows: [NSWindow] = []
    var models: [ObjectIdentifier: ExplorerModel] = [:]
    var keyMonitor: Any?
    var model: ExplorerModel? {
        if let key = NSApp.keyWindow, key === PreviewController.shared.window { return nil }
        if let window = NSApp.mainWindow, let model = models[ObjectIdentifier(window)] { return model }
        return windows.last.flatMap { models[ObjectIdentifier($0)] }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenus(); createWindow()
        NSApp.activate(ignoringOtherApps: true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = event.window, self.models[ObjectIdentifier(window)] != nil, let m = self.models[ObjectIdentifier(window)] else { return event }
            if event.modifierFlags.contains(.control) && event.keyCode == 48 { m.nextTab(event.modifierFlags.contains(.shift) ? -1 : 1); return nil }
            let editing = window.firstResponder is NSTextView
            if event.modifierFlags.contains(.control) && !editing {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "c": m.copy(); return nil; case "x": m.copy(cut: true); return nil; case "v": m.paste(); return nil
                case "a": m.selection = Set(m.entries.map(\.url)); return nil; case "z": m.undo(); return nil
                case "l": m.addressFocusToken += 1; return nil; case "f": m.searchFocusToken += 1; return nil
                case "t": m.newTab(); return nil; case "w": m.closeTab(m.activeID); return nil
                case "n" where event.modifierFlags.contains(.shift): m.newFolder(); return nil
                default: break
                }
            }
            return event
        }
    }
    func createWindow(_ url: URL? = nil) {
        let start: URL?
        if let url { start = url }
        else if let index = CommandLine.arguments.firstIndex(of: "--open"), CommandLine.arguments.count > index + 1 { start = URL(fileURLWithPath: CommandLine.arguments[index + 1]) }
        else { start = nil }
        let m = ExplorerModel(startURL: start)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 790), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "ExplorerMac — 资源管理器"; window.minSize = NSSize(width: 940, height: 580); window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ExplorerView(model: m)); window.delegate = self; window.tabbingMode = .disallowed
        if windows.isEmpty { window.setFrameAutosaveName("ExplorerMacMainWindow") }; window.center(); windows.append(window); models[ObjectIdentifier(window)] = m
        window.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if !flag { createWindow() }; return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if models.values.contains(where: \.busy) { model?.showMessage("文件操作仍在进行", "请等待操作完成后再退出，以免中断文件传输。"); return .terminateCancel }
        return .terminateNow
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if models[ObjectIdentifier(sender)]?.busy == true { model?.showMessage("文件操作仍在进行", "请等待操作完成后再关闭窗口。"); return false }; return true
    }
    func windowWillClose(_ notification: Notification) { if let window = notification.object as? NSWindow { models.removeValue(forKey: ObjectIdentifier(window)); windows.removeAll { $0 === window } } }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for path in filenames { let url = URL(fileURLWithPath: path); if FileEntry(url).navigable { if let model { model.navigate(url) } else { createWindow(url) } } }; sender.reply(toOpenOrPrint: .success)
    }
    func setupMenus() {
        let bar = NSMenu(); NSApp.mainMenu = bar
        func submenu(_ title: String) -> NSMenu { let item = NSMenuItem(); item.title = title; let menu = NSMenu(title: title); item.submenu = menu; bar.addItem(item); return menu }
        func item(_ menu: NSMenu, _ title: String, _ selector: Selector, _ key: String = "", _ flags: NSEvent.ModifierFlags = .command) { let i = NSMenuItem(title: title, action: selector, keyEquivalent: key); i.keyEquivalentModifierMask = flags; i.target = self; menu.addItem(i) }
        let app = submenu("ExplorerMac")
        item(app, "关于 ExplorerMac", #selector(about)); app.addItem(.separator()); item(app, "隐藏 ExplorerMac", #selector(hide), "h"); app.addItem(.separator()); item(app, "退出 ExplorerMac", #selector(quit), "q")
        let file = submenu("文件")
        item(file, "新建窗口", #selector(newWindow), "n"); item(file, "新建标签页", #selector(newTab), "t"); item(file, "打开文件夹…", #selector(chooseFolder), "o")
        item(file, "新建文件夹", #selector(newFolder), "n", [.command, .shift]); item(file, "新建文本文件", #selector(newText)); file.addItem(.separator())
        item(file, "打开所选项目", #selector(openSelected), "\r"); item(file, "快速预览", #selector(preview), "y"); item(file, "重命名", #selector(rename)); item(file, "属性", #selector(properties), "i"); file.addItem(.separator()); item(file, "关闭标签页", #selector(closeTab), "w")
        let edit = submenu("编辑")
        item(edit, "撤销上次文件操作", #selector(undo), "z"); edit.addItem(.separator()); item(edit, "剪切", #selector(cut), "x"); item(edit, "复制", #selector(copyFiles), "c"); item(edit, "粘贴", #selector(paste), "v"); item(edit, "全选", #selector(selectAll), "a")
        item(edit, "复制路径", #selector(copyPaths), "c", [.command, .shift]); edit.addItem(.separator()); item(edit, "复制到…", #selector(copyTo)); item(edit, "移动到…", #selector(moveTo)); item(edit, "移到废纸篓", #selector(trash), "\u{8}")
        let view = submenu("显示")
        item(view, "详细信息", #selector(details), "1"); item(view, "中等图标", #selector(small), "2"); item(view, "大图标", #selector(large), "3"); item(view, "超大图标", #selector(huge), "4"); view.addItem(.separator()); item(view, "显示 / 隐藏预览窗格", #selector(togglePreview), "p", [.command, .option]); item(view, "显示 / 隐藏隐藏文件", #selector(hidden), ".", [.command, .shift]); item(view, "刷新", #selector(refresh), "r")
        let go = submenu("前往")
        item(go, "后退", #selector(back), "["); item(go, "前进", #selector(forward), "]"); item(go, "上一级", #selector(up), String(UnicodeScalar(NSUpArrowFunctionKey)!), [.command]); go.addItem(.separator()); item(go, "输入路径", #selector(address), "l"); item(go, "搜索", #selector(search), "f"); item(go, "主文件夹", #selector(home), "h", [.command, .shift]); item(go, "下载", #selector(downloads), "l", [.command, .option]); item(go, "在访达中显示", #selector(reveal))
        let help = submenu("帮助"); item(help, "使用说明和快捷键", #selector(helpAction)); NSApp.helpMenu = help
    }
    func forwardText(_ action: Selector) -> Bool {
        guard let view = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        if action == #selector(undo) { view.undoManager?.undo() } else { NSApp.sendAction(action, to: view, from: nil) }; return true
    }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "ExplorerMac", .applicationVersion: "1.0.0", .credits: NSAttributedString(string: "Windows 风格的 macOS 原生文件管理器\nSwift · AppKit · Quick Look\n独立开发应用，与 Microsoft / Apple 无隶属关系。")]) }
    @objc func hide() { NSApp.hide(nil) }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func newWindow() { createWindow(model?.currentURL) }
    @objc func newTab() { model?.newTab() }
    @objc func closeTab() { if let m = model { m.closeTab(m.activeID) } }
    @objc func chooseFolder() { model?.chooseFolder() }
    @objc func newFolder() { model?.newFolder() }
    @objc func newText() { model?.newTextFile() }
    @objc func openSelected() { model?.openSelection() }
    @objc func preview() { model?.quickLook() }
    @objc func rename() { model?.rename() }
    @objc func properties() { model?.properties() }
    @objc func undo() { if !forwardText(#selector(undo)) { model?.undo() } }
    @objc func cut() { if !forwardText(#selector(NSText.cut(_:))) { model?.copy(cut: true) } }
    @objc func copyFiles() { if !forwardText(#selector(NSText.copy(_:))) { model?.copy() } }
    @objc func paste() { if !forwardText(#selector(NSText.paste(_:))) { model?.paste() } }
    @objc func selectAll() { if !forwardText(#selector(NSText.selectAll(_:))), let m = model { m.selection = Set(m.entries.map(\.url)) } }
    @objc func copyPaths() { model?.copyPaths() }
    @objc func copyTo() { model?.pickTransfer(move: false) }
    @objc func moveTo() { model?.pickTransfer(move: true) }
    @objc func trash() { model?.deleteSelection() }
    @objc func details() { model?.viewMode = .details }
    @objc func small() { model?.viewMode = .small }
    @objc func large() { model?.viewMode = .large }
    @objc func huge() { model?.viewMode = .huge }
    @objc func togglePreview() { model?.previewVisible.toggle() }
    @objc func hidden() { model?.showHidden.toggle() }
    @objc func refresh() { model?.refresh() }
    @objc func back() { model?.back() }
    @objc func forward() { model?.forward() }
    @objc func up() { model?.up() }
    @objc func address() { model?.addressFocusToken += 1 }
    @objc func search() { model?.searchFocusToken += 1 }
    @objc func home() { model?.navigate(FileManager.default.homeDirectoryForCurrentUser) }
    @objc func downloads() { model?.navigate(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")) }
    @objc func reveal() { model?.reveal() }
    @objc func helpAction() { Self.showHelp() }
    func openRecent() {
        let recent = NSDocumentController.shared.recentDocumentURLs
        let menu = NSMenu(); menu.autoenablesItems = false
        if recent.isEmpty { menu.action("尚无最近访问的项目", enabled: false) {} }
        for url in recent.prefix(20) { menu.action(url.lastPathComponent, symbol: FileEntry(url).navigable ? "folder" : "doc") { self.model?.openURL(url) } }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    static func showHelp() {
        let a = NSAlert(); a.messageText = "ExplorerMac 使用说明"
        a.informativeText = "双击 / Enter：打开文件或文件夹\n空格：大预览；← → 切换；Esc 关闭\n⌘ / Ctrl + C、X、V：复制、剪切、粘贴\n⌘ / Ctrl + A：全选；Shift / ⌘ 点击：多选\n⌘ / Ctrl + Z：撤销上次文件操作\nF2：重命名；F5 / ⌘R：刷新\n⌘⌫ / 向前 Delete：移到废纸篓\nBackspace：后退；⌥← / → / ↑：导航\n⌘ / Ctrl + L：输入路径；⌘ / Ctrl + F：搜索\n⌘ / Ctrl + T：新标签页；⌘W：关闭标签页\nCtrl + Tab / Ctrl + Shift + Tab：切换标签页\n⌘1–4：详情 / 中 / 大 / 超大图标\n⌘⇧N：新建文件夹；⌘⇧.：隐藏文件\n⌥⌘P：显示 / 隐藏预览窗格\n\n拖放默认为复制；移动请使用剪切粘贴或“移动到”。\n重名自动保留两份，不覆盖已有文件。\n搜索默认匹配当前文件夹的名称，下拉箭头可包含子文件夹。\n“最近使用”仅包含在本应用访问过的项目。"
        a.addButton(withTitle: "知道了"); a.runModal()
    }
}

@main
struct ExplorerMain {
    static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.regular); app.delegate = AppDelegate.shared; app.run()
    }
}
