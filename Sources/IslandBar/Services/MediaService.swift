import AppKit
import Combine
import Foundation
import ImageIO

private enum ScriptRunner {
    static func run(_ source: String) -> (String?, Int?) {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        let number = error?[NSAppleScript.errorNumber] as? Int
        return (result?.stringValue, number)
    }

    static func musicArtwork() -> (String?, Data?, Int?) {
        let source = """
        tell application "Music"
            set currentItem to current track
            set trackID to ""
            try
                set trackID to persistent ID of currentItem
            end try
            if (count of artworks of currentItem) is 0 then return {trackID, missing value}
            try
                return {trackID, raw data of artwork 1 of currentItem}
            on error
                try
                    return {trackID, data of artwork 1 of currentItem}
                on error
                    return {trackID, missing value}
                end try
            end try
        end tell
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        let descriptor = result?.atIndex(2)
        let data = descriptor.flatMap { $0.data.isEmpty ? nil : $0.data }
        return (
            result?.atIndex(1)?.stringValue,
            data,
            error?[NSAppleScript.errorNumber] as? Int
        )
    }
}

final class MediaService: ObservableObject {
    @Published private(set) var track = MediaTrack.empty
    @Published private(set) var artwork: NSImage?
    @Published private(set) var artworkIdentity = ""
    @Published private(set) var accentColor = NSColor(srgbRed: 0.35, green: 0.82, blue: 0.72, alpha: 1)
    @Published private(set) var secondaryAccentColor = NSColor(srgbRed: 0.45, green: 0.58, blue: 1, alpha: 1)
    @Published private(set) var automationDenied = false

    private let queue = DispatchQueue(label: "local.islandbar.media", qos: .utility)
    private let artworkQueue = DispatchQueue(label: "local.islandbar.artwork", qos: .userInitiated)
    private var timer: Timer?
    private var pollInFlight = false
    private var artworkTask: URLSessionDataTask?
    private var requestedArtworkIdentity = ""
    private var artworkCache: [String: ArtworkResult] = [:]
    private var usesTestingPreview = false

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        if let timer {
            timer.tolerance = 0.15
            RunLoop.main.add(timer, forMode: .common)
        }
        poll()
    }

    deinit {
        artworkTask?.cancel()
        timer?.invalidate()
    }

    func poll() {
        guard !pollInFlight, !usesTestingPreview else { return }
        let spotifyRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
        let musicRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
        guard spotifyRunning || musicRunning else {
            resetMedia()
            return
        }

        pollInFlight = true
        queue.async { [weak self] in
            var candidates: [(MediaTrack, Int?)] = []
            if spotifyRunning { candidates.append(Self.spotifySnapshot()) }
            if musicRunning { candidates.append(Self.musicSnapshot()) }
            let chosen = candidates.first(where: { $0.0.isPlaying })
                ?? candidates.first(where: { $0.0.hasContent })
            DispatchQueue.main.async {
                guard let self, !self.usesTestingPreview else { return }
                self.pollInFlight = false
                guard let chosen else {
                    self.resetMedia()
                    return
                }
                if chosen.1 == -1743 { self.automationDenied = true }
                else if chosen.1 == nil { self.automationDenied = false }

                let previousIdentity = self.track.identity
                self.track = chosen.0
                if chosen.0.identity != previousIdentity || self.artworkIdentity != chosen.0.identity {
                    self.requestArtwork(for: chosen.0)
                }
            }
        }
    }

    func playPause() {
        perform(command: "playpause", mediaKey: 16)
    }

    func previous() {
        perform(command: "previous track", mediaKey: 18)
    }

    func next() {
        perform(command: "next track", mediaKey: 17)
    }

    func seek(progress: Double) {
        guard track.duration > 0 else { return }
        let seconds = Int(track.duration * min(max(progress, 0), 1))
        let appName = track.source == .spotify ? "Spotify" : "Music"
        queue.async {
            _ = ScriptRunner.run("tell application \"\(appName)\" to set player position to \(seconds)")
        }
        track.position = Double(seconds)
        track.sampledAt = Date()
    }

    func installTestingPreview() {
        usesTestingPreview = true
        timer?.invalidate()
        timer = nil
        artworkTask?.cancel()
        artwork = nil
        artworkIdentity = "testing-preview"
        accentColor = NSColor(srgbRed: 0.58, green: 0.92, blue: 0.32, alpha: 1)
        secondaryAccentColor = NSColor(srgbRed: 0.20, green: 0.76, blue: 0.58, alpha: 1)
        track = MediaTrack(
            source: .spotify,
            title: "Night Drive",
            artist: "IslandBar Demo",
            album: "Demo Session",
            duration: 143,
            position: 72,
            isPlaying: true,
            artworkReference: "preview",
            sampledAt: Date()
        )
    }

    private func perform(command: String, mediaKey: Int32) {
        let source = track.source
        if source == .music || source == .spotify {
            let appName = source == .spotify ? "Spotify" : "Music"
            queue.async { [weak self] in
                let result = ScriptRunner.run("tell application \"\(appName)\" to \(command)")
                DispatchQueue.main.async {
                    if result.1 == -1743 { self?.automationDenied = true }
                    self?.poll()
                }
            }
        } else {
            sendMediaKey(mediaKey)
        }
    }

    private func sendMediaKey(_ key: Int32) {
        let downData = Int((key << 16) | (0xA << 8))
        let upData = Int((key << 16) | (0xB << 8))
        let down = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: downData,
            data2: -1
        )
        let up = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: upData,
            data2: -1
        )
        down?.cgEvent?.post(tap: .cghidEventTap)
        up?.cgEvent?.post(tap: .cghidEventTap)
    }

    private func resetMedia() {
        guard track != .empty || artwork != nil else { return }
        track = .empty
        artworkTask?.cancel()
        requestedArtworkIdentity = ""
        artworkIdentity = ""
        artwork = nil
    }

    private func requestArtwork(for newTrack: MediaTrack) {
        let identity = newTrack.identity
        guard newTrack.hasContent, requestedArtworkIdentity != identity else { return }
        requestedArtworkIdentity = identity
        artworkTask?.cancel()

        if let cached = artworkCache[identity] {
            apply(cached, identity: identity)
            return
        }

        artwork = nil
        artworkIdentity = identity

        switch newTrack.source {
        case .spotify:
            guard let url = URL(string: newTrack.artworkReference),
                  url.scheme == "https" else { return }
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 12
            artworkTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
                guard let self,
                      let data,
                      data.count <= 15_000_000,
                      let response = response as? HTTPURLResponse,
                      response.statusCode == 200,
                      let result = Self.decodeArtwork(data) else { return }
                DispatchQueue.main.async {
                    guard self.track.identity == identity else { return }
                    self.artworkCache[identity] = result
                    self.apply(result, identity: identity)
                }
            }
            artworkTask?.resume()

        case .music:
            let expectedReference = newTrack.artworkReference
            artworkQueue.async { [weak self] in
                let returned = ScriptRunner.musicArtwork()
                guard let self,
                      returned.2 != -1743,
                      let data = returned.1,
                      returned.0 == expectedReference || expectedReference.isEmpty,
                      let result = Self.decodeArtwork(data) else { return }
                DispatchQueue.main.async {
                    guard self.track.identity == identity else { return }
                    self.artworkCache[identity] = result
                    self.apply(result, identity: identity)
                }
            }

        default:
            break
        }
    }

    private func apply(_ result: ArtworkResult, identity: String) {
        artwork = result.image
        artworkIdentity = identity
        accentColor = result.primary
        secondaryAccentColor = result.secondary
    }

    private static func spotifySnapshot() -> (MediaTrack, Int?) {
        let script = """
        tell application "Spotify"
            if player state is stopped then return "stopped~~~Ничего не играет~~~Spotify~~~~~~0~~~0~~~"
            set currentItem to current track
            set trackName to name of currentItem
            set trackArtist to artist of currentItem
            set trackAlbum to album of currentItem
            set trackDuration to (duration of currentItem) / 1000
            set trackPosition to player position
            set coverURL to ""
            try
                set coverURL to artwork url of currentItem
            end try
            return (player state as text) & "~~~" & trackName & "~~~" & trackArtist & "~~~" & trackAlbum & "~~~" & (trackDuration as text) & "~~~" & (trackPosition as text) & "~~~" & coverURL
        end tell
        """
        let result = ScriptRunner.run(script)
        return (parse(result.0, source: .spotify), result.1)
    }

    private static func musicSnapshot() -> (MediaTrack, Int?) {
        let script = """
        tell application "Music"
            if player state is stopped then return "stopped~~~Ничего не играет~~~Apple Music~~~~~~0~~~0~~~"
            set currentItem to current track
            set trackName to name of currentItem
            set trackArtist to artist of currentItem
            set trackAlbum to album of currentItem
            set trackDuration to duration of currentItem
            set trackPosition to player position
            set trackIdentifier to ""
            try
                set trackIdentifier to persistent ID of currentItem
            end try
            return (player state as text) & "~~~" & trackName & "~~~" & trackArtist & "~~~" & trackAlbum & "~~~" & (trackDuration as text) & "~~~" & (trackPosition as text) & "~~~" & trackIdentifier
        end tell
        """
        let result = ScriptRunner.run(script)
        return (parse(result.0, source: .music), result.1)
    }

    private static func parse(_ value: String?, source: MediaTrack.Source) -> MediaTrack {
        guard let value else { return .empty }
        let fields = value.components(separatedBy: "~~~")
        guard fields.count >= 6, !fields[0].lowercased().contains("stopped") else { return .empty }
        return MediaTrack(
            source: source,
            title: fields[1],
            artist: fields[2],
            album: fields[3],
            duration: Double(fields[4].replacingOccurrences(of: ",", with: ".")) ?? 0,
            position: Double(fields[5].replacingOccurrences(of: ",", with: ".")) ?? 0,
            isPlaying: fields[0].lowercased().contains("playing"),
            artworkReference: fields.count > 6 ? fields[6] : "",
            sampledAt: Date()
        )
    }

    private static func decodeArtwork(_ data: Data) -> ArtworkResult? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 512
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
        let colors = dominantColors(from: thumbnail)
            ?? (
                NSColor(srgbRed: 0.35, green: 0.82, blue: 0.72, alpha: 1),
                NSColor(srgbRed: 0.45, green: 0.58, blue: 1, alpha: 1)
            )
        return ArtworkResult(image: image, primary: colors.0, secondary: colors.1)
    }

    private static func dominantColors(from image: CGImage) -> (NSColor, NSColor)? {
        let width = 32
        let height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return nil }

        var buckets = Array(repeating: ColorBucket(), count: 24)
        var neutral = ColorBucket()
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.45 else { continue }
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            let hsv = rgbToHSV(red: red, green: green, blue: blue)
            guard hsv.value > 0.08, hsv.value < 0.96 else { continue }
            neutral.add(red: red, green: green, blue: blue, weight: alpha * (0.35 + hsv.value))
            guard hsv.saturation > 0.16 else { continue }
            let bucketIndex = min(Int(hsv.hue * Double(buckets.count)), buckets.count - 1)
            let weight = alpha * (0.25 + pow(hsv.saturation, 1.35) * 2.2) * (0.45 + hsv.value)
            buckets[bucketIndex].add(red: red, green: green, blue: blue, weight: weight)
        }

        guard let primaryIndex = buckets.indices.max(by: { buckets[$0].weight < buckets[$1].weight }) else { return nil }
        let selected = buckets[primaryIndex].weight > 0 ? buckets[primaryIndex] : neutral
        guard selected.weight > 0 else { return nil }
        let primaryRGB = makeVivid(selected.rgb)

        let secondaryIndex = buckets.indices
            .filter { circularDistance($0, primaryIndex, count: buckets.count) >= 4 }
            .max(by: { buckets[$0].weight < buckets[$1].weight })
        let secondaryRGB: (Double, Double, Double)
        if let secondaryIndex, buckets[secondaryIndex].weight > selected.weight * 0.18 {
            secondaryRGB = makeVivid(buckets[secondaryIndex].rgb)
        } else {
            secondaryRGB = (
                min(primaryRGB.0 * 0.72 + 0.28, 1),
                min(primaryRGB.1 * 0.72 + 0.28, 1),
                min(primaryRGB.2 * 0.72 + 0.28, 1)
            )
        }

        return (
            NSColor(srgbRed: primaryRGB.0, green: primaryRGB.1, blue: primaryRGB.2, alpha: 1),
            NSColor(srgbRed: secondaryRGB.0, green: secondaryRGB.1, blue: secondaryRGB.2, alpha: 1)
        )
    }

    private static func rgbToHSV(red: Double, green: Double, blue: Double) -> (hue: Double, saturation: Double, value: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        var hue = 0.0
        if delta > 0 {
            if maximum == red { hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) }
            else if maximum == green { hue = (blue - red) / delta + 2 }
            else { hue = (red - green) / delta + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, maximum == 0 ? 0 : delta / maximum, maximum)
    }

    private static func makeVivid(_ rgb: (Double, Double, Double)) -> (Double, Double, Double) {
        let hsv = rgbToHSV(red: rgb.0, green: rgb.1, blue: rgb.2)
        let saturation = min(max(hsv.saturation, 0.48), 0.92)
        let value = min(max(hsv.value, 0.62), 0.94)
        let sector = hsv.hue * 6
        let index = Int(floor(sector)) % 6
        let fraction = sector - floor(sector)
        let p = value * (1 - saturation)
        let q = value * (1 - fraction * saturation)
        let t = value * (1 - (1 - fraction) * saturation)
        switch index {
        case 0: return (value, t, p)
        case 1: return (q, value, p)
        case 2: return (p, value, t)
        case 3: return (p, q, value)
        case 4: return (t, p, value)
        default: return (value, p, q)
        }
    }

    private static func circularDistance(_ lhs: Int, _ rhs: Int, count: Int) -> Int {
        let distance = abs(lhs - rhs)
        return min(distance, count - distance)
    }
}

private struct ArtworkResult {
    let image: NSImage
    let primary: NSColor
    let secondary: NSColor
}

private struct ColorBucket {
    var red = 0.0
    var green = 0.0
    var blue = 0.0
    var weight = 0.0

    mutating func add(red: Double, green: Double, blue: Double, weight: Double) {
        self.red += red * weight
        self.green += green * weight
        self.blue += blue * weight
        self.weight += weight
    }

    var rgb: (Double, Double, Double) {
        guard weight > 0 else { return (0.4, 0.4, 0.4) }
        return (red / weight, green / weight, blue / weight)
    }
}
