import AppKit
import Combine
import Foundation
import UserNotifications

@MainActor
final class FocusEngine: ObservableObject {
    @Published var mode: FocusMode = .pomodoro
    @Published var pomodoroPhase: PomodoroPhase = .work
    @Published var isRunning = false
    @Published var remaining: TimeInterval = 25 * 60
    @Published var elapsed: TimeInterval = 0
    @Published var workMinutes = 25
    @Published var restMinutes = 5
    @Published var countdownMinutes = 10

    var onCompleted: ((String, String) -> Void)?

    private var timer: Timer?
    private var lastTick = Date()
    private var requestedNotifications = false

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    var displayTime: TimeInterval {
        mode == .stopwatch ? elapsed : remaining
    }

    var progress: Double {
        switch mode {
        case .pomodoro:
            let total = TimeInterval((pomodoroPhase == .work ? workMinutes : restMinutes) * 60)
            return total > 0 ? 1 - remaining / total : 0
        case .countdown:
            let total = TimeInterval(countdownMinutes * 60)
            return total > 0 ? 1 - remaining / total : 0
        case .stopwatch:
            return elapsed.truncatingRemainder(dividingBy: 60) / 60
        }
    }

    func select(_ newMode: FocusMode) {
        guard mode != newMode else { return }
        isRunning = false
        mode = newMode
        reset()
    }

    func startPause() {
        isRunning.toggle()
        lastTick = Date()
        if isRunning { requestNotificationsIfNeeded() }
    }

    func reset() {
        isRunning = false
        switch mode {
        case .pomodoro:
            remaining = TimeInterval((pomodoroPhase == .work ? workMinutes : restMinutes) * 60)
        case .countdown:
            remaining = TimeInterval(countdownMinutes * 60)
        case .stopwatch:
            elapsed = 0
        }
    }

    func skipPomodoroPhase() {
        pomodoroPhase = pomodoroPhase == .work ? .rest : .work
        remaining = TimeInterval((pomodoroPhase == .work ? workMinutes : restMinutes) * 60)
        lastTick = Date()
    }

    func applyDurations() {
        workMinutes = min(max(workMinutes, 1), 120)
        restMinutes = min(max(restMinutes, 1), 60)
        countdownMinutes = min(max(countdownMinutes, 1), 240)
        reset()
    }

    private func tick() {
        guard isRunning else { return }
        let now = Date()
        let delta = min(now.timeIntervalSince(lastTick), 1)
        lastTick = now

        if mode == .stopwatch {
            elapsed += delta
            return
        }

        remaining = max(remaining - delta, 0)
        if remaining <= 0 { finishCurrentSession() }
    }

    private func finishCurrentSession() {
        isRunning = false
        NSSound.beep()

        let title: String
        let body: String
        if mode == .pomodoro {
            title = pomodoroPhase == .work ? "Фокус завершён" : "Перерыв завершён"
            pomodoroPhase = pomodoroPhase == .work ? .rest : .work
            body = pomodoroPhase == .rest ? "Пора немного отдохнуть." : "Можно начинать новый цикл."
            remaining = TimeInterval((pomodoroPhase == .work ? workMinutes : restMinutes) * 60)
        } else {
            title = "Таймер завершён"
            body = "Заданное время истекло."
            remaining = TimeInterval(countdownMinutes * 60)
        }

        onCompleted?(title, body)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func requestNotificationsIfNeeded() {
        guard !requestedNotifications else { return }
        requestedNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
