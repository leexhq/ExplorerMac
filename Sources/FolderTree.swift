import AppKit
import SwiftUI

enum FileArtwork {
    static let folder: NSImage = {
        let size = NSSize(width: 256, height: 208)
        let image = NSImage(size: size)
        image.lockFocus()
        let back = NSBezierPath(); back.move(to: NSPoint(x: 18, y: 40)); back.line(to: NSPoint(x: 18, y: 167)); back.curve(to: NSPoint(x: 32, y: 181), controlPoint1: NSPoint(x: 18, y: 177), controlPoint2: NSPoint(x: 24, y: 181)); back.line(to: NSPoint(x: 92, y: 181)); back.line(to: NSPoint(x: 112, y: 160)); back.line(to: NSPoint(x: 224, y: 160)); back.curve(to: NSPoint(x: 239, y: 146), controlPoint1: NSPoint(x: 234, y: 160), controlPoint2: NSPoint(x: 239, y: 156)); back.line(to: NSPoint(x: 239, y: 40)); back.close()
        NSGradient(starting: NSColor(calibratedRed: 0.96, green: 0.63, blue: 0.13, alpha: 1), ending: NSColor(calibratedRed: 1, green: 0.79, blue: 0.27, alpha: 1))!.draw(in: back, angle: 90)
        NSColor(calibratedWhite: 1, alpha: 0.9).setFill(); NSBezierPath(roundedRect: NSRect(x: 30, y: 84, width: 197, height: 62), xRadius: 6, yRadius: 6).fill()
        let face = NSBezierPath(roundedRect: NSRect(x: 17, y: 24, width: 223, height: 114), xRadius: 12, yRadius: 12)
        NSGraphicsContext.saveGraphicsState(); let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.16); shadow.shadowOffset = NSSize(width: 0, height: -4); shadow.shadowBlurRadius = 6; shadow.set()
        NSGradient(starting: NSColor(calibratedRed: 0.99, green: 0.69, blue: 0.17, alpha: 1), ending: NSColor(calibratedRed: 1, green: 0.86, blue: 0.39, alpha: 1))!.draw(in: face, angle: 90)
        NSGraphicsContext.restoreGraphicsState(); image.unlockFocus(); return image
    }()
    static func icon(_ entry: FileEntry) -> NSImage { entry.navigable ? folder : NSWorkspace.shared.icon(forFile: entry.url.path) }
}

struct FolderTreeNode: View {
    @ObservedObject var model: ExplorerModel
    let url: URL
    var title: String? = nil
    var depth = 0
    @State private var expanded = false
    @State private var children: [URL] = []
    @State private var loading = false
    @State private var failure = false
    @State private var truncated = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Button { expanded.toggle(); if expanded { load() } } label: { Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .semibold)).frame(width: 11, height: 27) }.buttonStyle(.plain).help("展开 / 折叠")
                Image(systemName: depth == 0 ? "externaldrive" : "folder.fill").font(.system(size: 13)).foregroundStyle(depth == 0 ? Color.secondary : Color(red: 0.91, green: 0.65, blue: 0.18))
                Text(title ?? url.lastPathComponent).font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 0)
            }.padding(.leading, CGFloat(min(depth, 8)) * 12 + 6).padding(.trailing, 6).frame(height: 31)
                .background(model.currentURL == url ? Color.accentColor.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle()).onTapGesture { model.navigate(url) }.help(url.path)
                .contextMenu { Button("打开") { model.navigate(url) }; Button("在新标签页打开") { model.newTab(url) }; Button("固定到快速访问") { model.pin(url) }; Button("刷新目录树") { load() } }
            if expanded {
                if loading { ProgressView().controlSize(.mini).padding(.leading, 28) }
                ForEach(children, id: \.path) { child in FolderTreeNode(model: model, url: child, depth: depth + 1) }
                if failure { Text("无法读取").font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading, CGFloat(depth * 12 + 25)) }
                if truncated { Button("更多文件夹…") { model.navigate(url) }.buttonStyle(.plain).font(.system(size: 10)).padding(.leading, 26) }
            }
        }.onChange(of: model.showHidden) { if expanded { load() } }
    }
    func load() {
        guard depth < 16 else { truncated = true; return }; loading = true
        let hidden = model.showHidden
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(FileEntry.keys), options: hidden ? [] : [.skipsHiddenFiles]).filter { FileEntry($0).navigable && !FileEntry($0).isLink }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                DispatchQueue.main.async { children = Array(urls.prefix(150)); truncated = urls.count > 150; loading = false; failure = false }
            } catch { DispatchQueue.main.async { children = []; loading = false; failure = true } }
        }
    }
}
