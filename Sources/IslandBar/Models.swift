import AppKit
import Foundation

enum IslandTab: String, CaseIterable, Identifiable {
    case home
    case shelf
    case clipboard
    case focus
    case day
    case tools
    case browser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Главная"
        case .shelf: return "Файлы"
        case .clipboard: return "Буфер"
        case .focus: return "Фокус"
        case .day: return "День"
        case .tools: return "Инструменты"
        case .browser: return "Поиск"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "sparkles"
        case .shelf: return "tray.full"
        case .clipboard: return "doc.on.clipboard"
        case .focus: return "timer"
        case .day: return "calendar"
        case .tools: return "square.grid.2x2"
        case .browser: return "globe"
        }
    }
}

enum IslandPresentation: Equatable {
    case hidden
    case compactMedia
    case compactFocus
    case activity
    case music
    case launcher
    case dashboard

    var isHoverSurface: Bool {
        self == .music || self == .launcher || self == .dashboard
    }
}

struct ShelfItem: Identifiable, Hashable, Codable {
    let id: UUID
    let path: String
    let addedAt: Date

    init(url: URL) {
        id = UUID()
        path = url.path
        addedAt = Date()
    }

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    var detail: String {
        guard exists,
              let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        else { return "Файл недоступен" }
        if values.isDirectory == true { return "Папка" }
        return ByteCountFormatter.string(fromByteCount: Int64(values.fileSize ?? 0), countStyle: .file)
    }
}

struct ClipboardEntry: Identifiable {
    enum Kind {
        case text
        case image
        case files
    }

    let id = UUID()
    let kind: Kind
    let text: String?
    let imageData: Data?
    let fileURLs: [URL]
    let capturedAt = Date()

    var title: String {
        switch kind {
        case .text:
            let compact = (text ?? "").replacingOccurrences(of: "\n", with: " ")
            return compact.isEmpty ? "Пустой текст" : compact
        case .image:
            return "Изображение"
        case .files:
            if fileURLs.count == 1 { return fileURLs[0].lastPathComponent }
            return "Файлы: \(fileURLs.count)"
        }
    }

    var symbol: String {
        switch kind {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .files: return "doc.on.doc"
        }
    }
}

struct DayEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let calendarTitle: String
    let color: NSColor
    let isAllDay: Bool
}

struct DayReminder: Identifiable, Hashable {
    let id: String
    let title: String
    let dueDate: Date?
    let calendarTitle: String
    let isCompleted: Bool
}

struct MediaTrack: Equatable {
    enum Source: String {
        case music = "Apple Music"
        case spotify = "Spotify"
        case system = "Медиаплеер"
        case none = ""
    }

    var source: Source = .none
    var title = "Ничего не играет"
    var artist = "Откройте Music или Spotify"
    var album = ""
    var duration: Double = 0
    var position: Double = 0
    var isPlaying = false
    var artworkReference = ""
    var sampledAt = Date()

    var identity: String {
        [source.rawValue, artworkReference, title, artist, album].joined(separator: "|")
    }

    var hasContent: Bool {
        source != .none && title != "Ничего не играет"
    }

    func position(at date: Date = Date()) -> Double {
        guard duration > 0 else { return 0 }
        let advanced = isPlaying ? date.timeIntervalSince(sampledAt) : 0
        return min(max(position + advanced, 0), duration)
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position(at: sampledAt) / duration, 0), 1)
    }

    static let empty = MediaTrack()
}

struct ShortcutItem: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let path: String

    init(name: String, path: String) {
        id = UUID()
        self.name = name
        self.path = path
    }

    var url: URL { URL(fileURLWithPath: path) }
}

struct SavedLink: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var address: String

    init(title: String, address: String) {
        id = UUID()
        self.title = title
        self.address = address
    }

    var url: URL? {
        if let direct = URL(string: address), direct.scheme != nil { return direct }
        return URL(string: "https://\(address)")
    }
}

enum FocusMode: String, CaseIterable, Identifiable {
    case pomodoro
    case countdown
    case stopwatch

    var id: String { rawValue }
    var title: String {
        switch self {
        case .pomodoro: return "Pomodoro"
        case .countdown: return "Таймер"
        case .stopwatch: return "Секундомер"
        }
    }
}

enum PomodoroPhase: String {
    case work
    case rest

    var title: String { self == .work ? "Фокус" : "Перерыв" }
    var symbol: String { self == .work ? "brain.head.profile" : "cup.and.saucer.fill" }
}

struct QuickActivity: Identifiable, Equatable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String
}

extension TimeInterval {
    var clockString: String {
        let value = max(Int(self.rounded(.down)), 0)
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let seconds = value % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}

extension Double {
    var transferRateString: String {
        ByteCountFormatter.string(fromByteCount: Int64(max(self, 0)), countStyle: .binary) + "/с"
    }
}
