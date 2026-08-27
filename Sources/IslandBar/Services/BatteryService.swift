import Combine
import Foundation
import IOKit.ps

@MainActor
final class BatteryService: ObservableObject {
    @Published private(set) var level: Int?
    @Published private(set) var isCharging = false
    @Published private(set) var isOnAC = false
    @Published private(set) var timeRemaining: TimeInterval?

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if let timer {
            timer.tolerance = 3
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func refresh() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            level = nil
            return
        }

        for source in list {
            guard let values = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let current = values[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = values[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }

            level = Int((Double(current) / Double(maximum) * 100).rounded())
            isCharging = values[kIOPSIsChargingKey] as? Bool ?? false
            isOnAC = (values[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            if let minutes = values[kIOPSTimeToEmptyKey] as? Int, minutes > 0 {
                timeRemaining = TimeInterval(minutes * 60)
            } else if let minutes = values[kIOPSTimeToFullChargeKey] as? Int, minutes > 0 {
                timeRemaining = TimeInterval(minutes * 60)
            } else {
                timeRemaining = nil
            }
            return
        }
        level = nil
    }

    var symbol: String {
        guard let level else { return "bolt.fill" }
        if isCharging { return "battery.100percent.bolt" }
        switch level {
        case 0..<15: return "battery.0percent"
        case 15..<40: return "battery.25percent"
        case 40..<70: return "battery.50percent"
        case 70..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
