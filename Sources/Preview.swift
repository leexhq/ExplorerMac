import AppKit
import SwiftUI
import Quartz
import ImageIO

struct QuickLookSurface: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView { let view = QLPreviewView(frame: .zero, style: .normal)!; view.autostarts = false; view.shouldCloseWithWindow = false; return view }
    func updateNSView(_ view: QLPreviewView, context: Context) { if (view.previewItem?.previewItemURL ?? nil) != url { view.previewItem = url as NSURL } }
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.close() }
}

struct ThumbnailImage: View {
    let entry: FileEntry
    let pixels: Int
    @State private var image: NSImage?
    var body: some View {
        Group { if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit) } else { ProgressView().controlSize(.small) } }
            .onAppear { load() }.onChange(of: entry) { image = nil; load() }
    }
    private func load() { ThumbnailStore.shared.load(entry, pixels: pixels) { image = $0 } }
}

final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var result = super.constrainBoundsRect(proposedBounds)
        if let doc = documentView {
            if doc.frame.width < result.width { result.origin.x = (doc.frame.width - result.width) / 2 }
            if doc.frame.height < result.height { result.origin.y = (doc.frame.height - result.height) / 2 }
        }
        return result
    }
}
final class ImagePreviewScroll: NSScrollView {
    let imageView = NSImageView()
    var loadedURL: URL?
    var requestedZoom: Double = 0
    var zoomRevision = -1
    var fitting = true
    var imagePixels = NSSize.zero
    var generation = UUID()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hasVerticalScroller = true; hasHorizontalScroller = true; autohidesScrollers = true
        allowsMagnification = true; minMagnification = 0.005; maxMagnification = 8
        backgroundColor = .textBackgroundColor
        contentView = CenteringClipView(frame: .zero)
        imageView.imageScaling = .scaleProportionallyUpOrDown; documentView = imageView
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); if fitting { fit() } }
    override func magnify(with event: NSEvent) { fitting = false; super.magnify(with: event) }
    func fit() {
        guard imagePixels.width > 0, contentSize.width > 0 else { return }
        let value = min(1, min((contentSize.width - 20) / imagePixels.width, (contentSize.height - 20) / imagePixels.height))
        if abs(magnification - max(0.005, value)) > 0.001 { magnification = max(0.005, value) }
    }
    func load(_ url: URL, zoom: Double, revision: Int) {
        if requestedZoom != zoom || zoomRevision != revision { requestedZoom = zoom; zoomRevision = revision; fitting = zoom == 0; if fitting { fit() } else { magnification = CGFloat(zoom) } }
        guard loadedURL != url else { return }
        loadedURL = url; fitting = zoom == 0; let token = UUID(); generation = token; imageView.image = nil
        DispatchQueue.global(qos: .userInitiated).async {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 8192, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return }
            let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            DispatchQueue.main.async {
                guard self.generation == token else { return }
                self.imagePixels = image.size; self.imageView.frame = NSRect(origin: .zero, size: image.size); self.imageView.image = image
                if self.requestedZoom == 0 { self.fit() } else { self.magnification = self.requestedZoom }
            }
        }
    }
}
struct ImageZoomSurface: NSViewRepresentable {
    let url: URL; let zoom: Double; let revision: Int
    func makeNSView(context: Context) -> ImagePreviewScroll { ImagePreviewScroll(frame: .zero) }
    func updateNSView(_ view: ImagePreviewScroll, context: Context) { view.load(url, zoom: zoom, revision: revision) }
}

final class PreviewState: ObservableObject {
    @Published var entries: [FileEntry] = []
    @Published var index = 0
    @Published var zoom = 0.0
    @Published var zoomRevision = 0
    var entry: FileEntry? { entries.indices.contains(index) ? entries[index] : nil }
    func step(_ offset: Int) { guard !entries.isEmpty else { return }; index = (index + offset + entries.count) % entries.count; zoom = 0 }
}
struct PreviewWindowContent: View {
    @ObservedObject var state: PreviewState
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { state.step(-1) } label: { Image(systemName: "chevron.left") }.help("上一项 ←")
                Button { state.step(1) } label: { Image(systemName: "chevron.right") }.help("下一项 →")
                Text("\(state.index + 1) / \(state.entries.count)").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                if state.entry?.isImage == true {
                    Button("适应窗口") { state.zoom = 0; state.zoomRevision += 1 }
                    Button("100%") { state.zoom = 1; state.zoomRevision += 1 }
                    Button { state.zoom = max(0.05, (state.zoom == 0 ? 1 : state.zoom) / 1.4) } label: { Image(systemName: "minus.magnifyingglass") }
                    Button { state.zoom = min(8, (state.zoom == 0 ? 0.5 : state.zoom) * 1.4) } label: { Image(systemName: "plus.magnifyingglass") }
                }
                Button("使用默认应用打开") { if let url = state.entry?.url { NSWorkspace.shared.open(url) } }
            }.buttonStyle(.borderless).padding(14).background(Color(nsColor: .windowBackgroundColor))
            Divider()
            if let entry = state.entry {
                if entry.isImage { ImageZoomSurface(url: entry.url, zoom: state.zoom, revision: state.zoomRevision).frame(maxWidth: .infinity, maxHeight: .infinity) }
                else { QuickLookSurface(url: entry.url).id(entry.url).frame(maxWidth: .infinity, maxHeight: .infinity) }
                Divider()
                HStack { Text(entry.name).lineLimit(1); Spacer(); Text(entry.sizeText); Text("← → 切换 · Esc 关闭").foregroundStyle(.secondary) }.font(.system(size: 12)).padding(12)
            }
        }.frame(minWidth: 640, minHeight: 420)
    }
}
final class PreviewController: NSObject, NSWindowDelegate {
    static let shared = PreviewController()
    let state = PreviewState()
    var window: NSWindow?
    var monitor: Any?
    func show(entries: [FileEntry], selected: URL) {
        guard !entries.isEmpty else { return }
        state.entries = entries; state.index = entries.firstIndex { $0.url == selected } ?? 0; state.zoom = 0
        if window == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 920, height: 680), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            panel.title = "快速预览"; panel.isReleasedWhenClosed = false; panel.delegate = self
            panel.contentView = NSHostingView(rootView: PreviewWindowContent(state: state)); panel.center(); window = panel
        }
        window?.makeKeyAndOrderFront(nil)
        if monitor == nil { monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            switch event.keyCode { case 53, 49: self.window?.close(); return nil; case 123: self.state.step(-1); return nil; case 124: self.state.step(1); return nil; default: return event }
        } }
    }
    func windowWillClose(_ notification: Notification) { if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }; window?.contentView = nil; window = nil; state.entries = [] }
}

struct PreviewSidebar: View {
    @ObservedObject var model: ExplorerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("预览").font(.system(size: 13, weight: .semibold)); Spacer(); Button { model.previewVisible = false } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.borderless).help("关闭预览窗格") }.padding(17)
            Divider()
            if let entry = model.selectedEntries.first {
                VStack(alignment: .leading, spacing: 15) {
                    if entry.isImage || entry.navigable {
                        ThumbnailImage(entry: entry, pixels: 1024).id(entry.url).frame(maxWidth: .infinity).frame(height: 230).padding(8).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    } else { QuickLookSurface(url: entry.url).id(entry.url).frame(height: 245).clipped() }
                    Text(entry.name).font(.system(size: 16, weight: .semibold)).textSelection(.enabled).lineLimit(3)
                    Text(entry.kind).font(.system(size: 12)).foregroundStyle(.secondary)
                    Divider()
                    meta("大小", entry.sizeText)
                    meta("修改日期", FileBrowser.Coordinator.dateFormatter.string(from: entry.modified))
                    meta("位置", entry.url.deletingLastPathComponent().path)
                    if model.selection.count > 1 { Text("另有 \(model.selection.count - 1) 项已选中").font(.system(size: 12)).foregroundStyle(.secondary) }
                    Button { model.quickLook() } label: { Label("打开大预览", systemImage: "arrow.up.left.and.arrow.down.right").frame(maxWidth: .infinity) }.controlSize(.large)
                    Text("空格预览 · 方向键切换\n图片支持缩放，文档使用系统预览").font(.system(size: 11)).foregroundStyle(.tertiary).lineSpacing(4)
                }.padding(17)
            } else {
                Spacer()
                VStack(spacing: 12) { Image(systemName: "doc.text.image").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(.tertiary); Text("选择文件以预览").font(.system(size: 14)); Text("查看图片、PDF 和更多文件\n按空格打开大预览").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5) }.frame(maxWidth: .infinity)
                Spacer()
            }
            Spacer(minLength: 0)
        }.frame(minWidth: 240, idealWidth: 270, maxWidth: 320).background(Color(nsColor: .textBackgroundColor))
    }
    func meta(_ name: String, _ value: String) -> some View { HStack(alignment: .top) { Text(name).foregroundStyle(.secondary).frame(width: 65, alignment: .leading); Text(value).textSelection(.enabled).lineLimit(3); Spacer(minLength: 0) }.font(.system(size: 11)) }
}
