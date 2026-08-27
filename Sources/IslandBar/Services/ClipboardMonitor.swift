import AppKit
import Combine
import Foundation

@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published var isEnabled = true

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let maximumEntries = 40

    init() {
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func clear() {
        entries.removeAll()
    }

    func copy(_ entry: ClipboardEntry) {
        pasteboard.clearContents()
        switch entry.kind {
        case .text:
            pasteboard.setString(entry.text ?? "", forType: .string)
        case .image:
            if let data = entry.imageData, let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        case .files:
            pasteboard.writeObjects(entry.fileURLs as [NSURL])
        }
        lastChangeCount = pasteboard.changeCount
    }

    func remove(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    private func poll() {
        guard isEnabled, pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        guard pasteboard.data(forType: concealed) == nil,
              pasteboard.data(forType: transient) == nil else { return }

        if let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]),
           let urls = objects as? [URL], !urls.isEmpty {
            add(ClipboardEntry(kind: .files, text: nil, imageData: nil, fileURLs: urls))
            return
        }

        if let image = NSImage(pasteboard: pasteboard), let data = image.tiffRepresentation {
            add(ClipboardEntry(kind: .image, text: nil, imageData: data, fileURLs: []))
            return
        }

        if let value = pasteboard.string(forType: .string), !value.isEmpty {
            let limited = String(value.prefix(100_000))
            add(ClipboardEntry(kind: .text, text: limited, imageData: nil, fileURLs: []))
        }
    }

    private func add(_ entry: ClipboardEntry) {
        if let first = entries.first {
            switch (first.kind, entry.kind) {
            case (.text, .text) where first.text == entry.text: return
            case (.files, .files) where first.fileURLs == entry.fileURLs: return
            case (.image, .image) where first.imageData == entry.imageData: return
            default: break
            }
        }
        entries.insert(entry, at: 0)
        if entries.count > maximumEntries { entries.removeLast(entries.count - maximumEntries) }
    }
}
