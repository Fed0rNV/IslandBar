import Combine
import CoreWLAN
import Darwin
import Foundation

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var downloadRate: Double = 0
    @Published private(set) var uploadRate: Double = 0
    @Published private(set) var downloadHistory = Array(repeating: 0.0, count: 36)
    @Published private(set) var uploadHistory = Array(repeating: 0.0, count: 36)
    @Published private(set) var wifiRSSI: Int? = nil

    private var lastReceived: UInt64 = 0
    private var lastSent: UInt64 = 0
    private var lastDate = Date()
    private var timer: Timer?

    init() {
        let totals = byteTotals()
        lastReceived = totals.received
        lastSent = totals.sent
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if let timer {
            timer.tolerance = 0.15
            RunLoop.main.add(timer, forMode: .common)
        }
        refreshSignal()
    }

    private func refresh() {
        let now = Date()
        let delta = max(now.timeIntervalSince(lastDate), 0.1)
        let totals = byteTotals()
        downloadRate = totals.received >= lastReceived ? Double(totals.received - lastReceived) / delta : 0
        uploadRate = totals.sent >= lastSent ? Double(totals.sent - lastSent) / delta : 0
        lastReceived = totals.received
        lastSent = totals.sent
        lastDate = now

        downloadHistory.append(downloadRate)
        uploadHistory.append(uploadRate)
        if downloadHistory.count > 36 { downloadHistory.removeFirst(downloadHistory.count - 36) }
        if uploadHistory.count > 36 { uploadHistory.removeFirst(uploadHistory.count - 36) }
        refreshSignal()
    }

    private func refreshSignal() {
        guard let interface = CWWiFiClient.shared().interface() else {
            wifiRSSI = nil
            return
        }
        let value = interface.rssiValue()
        wifiRSSI = value == 0 ? nil : value
    }

    private func byteTotals() -> (received: UInt64, sent: UInt64) {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let first = addressPointer else { return (0, 0) }
        defer { freeifaddrs(addressPointer) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            let isUsable = (flags & IFF_UP) != 0 && (flags & IFF_LOOPBACK) == 0
            if isUsable, let rawData = interface.ifa_data {
                let data = rawData.assumingMemoryBound(to: if_data.self).pointee
                received += UInt64(data.ifi_ibytes)
                sent += UInt64(data.ifi_obytes)
            }
            cursor = interface.ifa_next
        }
        return (received, sent)
    }
}
