import SwiftUI

struct FocusView: View {
    @ObservedObject var engine: FocusEngine

    var body: some View {
        HStack(spacing: 22) {
            VStack(spacing: 14) {
                Picker("Режим", selection: Binding(
                    get: { engine.mode },
                    set: { engine.select($0) }
                )) {
                    ForEach(FocusMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.075), lineWidth: 13)
                    Circle()
                        .trim(from: 0, to: max(min(engine.progress, 1), engine.mode == .stopwatch ? 0.01 : 0))
                        .stroke(
                            AngularGradient(
                                colors: [IslandPalette.accent, IslandPalette.purple, IslandPalette.mint, IslandPalette.accent],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 13, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.12), value: engine.progress)
                    VStack(spacing: 5) {
                        Image(systemName: modeSymbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(IslandPalette.mint)
                        Text(engine.displayTime.clockString)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(modeSubtitle)
                            .font(.caption)
                            .foregroundStyle(IslandPalette.secondary)
                    }
                }
                .frame(width: 205, height: 205)

                HStack(spacing: 13) {
                    Button(action: engine.reset) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(RoundIconButtonStyle(size: 40))

                    Button(action: engine.startPause) {
                        Label(engine.isRunning ? "Пауза" : "Старт", systemImage: engine.isRunning ? "pause.fill" : "play.fill")
                            .font(.headline)
                            .frame(minWidth: 78)
                    }
                    .buttonStyle(IslandButtonStyle(tint: IslandPalette.accent.opacity(0.66)))

                    if engine.mode == .pomodoro {
                        Button(action: engine.skipPomodoroPhase) {
                            Image(systemName: "forward.end.fill")
                        }
                        .buttonStyle(RoundIconButtonStyle(size: 40))
                        .help("Следующий этап")
                    }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                Text("Параметры")
                    .font(.headline)

                if engine.mode == .pomodoro {
                    DurationStepper(
                        title: "Работа",
                        symbol: "brain.head.profile",
                        value: $engine.workMinutes,
                        range: 1...120,
                        tint: IslandPalette.accent
                    )
                    DurationStepper(
                        title: "Перерыв",
                        symbol: "cup.and.saucer.fill",
                        value: $engine.restMinutes,
                        range: 1...60,
                        tint: IslandPalette.mint
                    )
                    .onChange(of: engine.workMinutes) { _, _ in engine.applyDurations() }
                    .onChange(of: engine.restMinutes) { _, _ in engine.applyDurations() }
                } else if engine.mode == .countdown {
                    DurationStepper(
                        title: "Длительность",
                        symbol: "timer",
                        value: $engine.countdownMinutes,
                        range: 1...240,
                        tint: IslandPalette.purple
                    )
                    .onChange(of: engine.countdownMinutes) { _, _ in engine.applyDurations() }
                } else {
                    Label("Секундомер считает время, пока IslandBar запущен. Его можно свернуть — отсчёт продолжится.", systemImage: "stopwatch")
                        .font(.subheadline)
                        .foregroundStyle(IslandPalette.secondary)
                }

                Divider().overlay(Color.white.opacity(0.1))

                Label("По завершении прозвучит сигнал и появится уведомление. Разрешение запрашивается только при первом запуске таймера.", systemImage: "bell.badge")
                    .font(.caption)
                    .foregroundStyle(IslandPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .islandCard(padding: 16, cornerRadius: 20)
        }
    }

    private var modeSymbol: String {
        switch engine.mode {
        case .pomodoro: return engine.pomodoroPhase.symbol
        case .countdown: return "timer"
        case .stopwatch: return "stopwatch.fill"
        }
    }

    private var modeSubtitle: String {
        engine.mode == .pomodoro ? engine.pomodoroPhase.title : engine.mode.title
    }
}

private struct DurationStepper: View {
    let title: String
    let symbol: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(0.14)))
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Stepper(value: $value, in: range) {
                Text("\(value) мин")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 58, alignment: .trailing)
            }
            .labelsHidden()
            Text("\(value) мин")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .frame(width: 58, alignment: .trailing)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.055)))
    }
}

struct DayView: View {
    @ObservedObject var service: CalendarService
    @State private var reminderTitle = ""
    @State private var reminderDate = Date().addingTimeInterval(3600)
    @State private var hasDueDate = true

    var body: some View {
        switch service.accessState {
        case .unknown, .denied:
            permissionView
        case .loading:
            ProgressView("Запрашиваем доступ…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 10) {
                EmptyStateView(symbol: "calendar.badge.exclamationmark", title: "Календарь недоступен", detail: message)
                Button("Попробовать снова", action: service.requestAccess)
                    .buttonStyle(IslandButtonStyle())
            }
        case .granted:
            dayContent
        }
    }

    private var permissionView: some View {
        VStack(spacing: 14) {
            EmptyStateView(
                symbol: "calendar.badge.plus",
                title: "Подключить ваш день",
                detail: "События и напоминания читаются через EventKit и остаются только на этом Mac"
            )
            Button(action: service.requestAccess) {
                Label("Разрешить календарь и напоминания", systemImage: "checkmark.shield")
            }
            .buttonStyle(IslandButtonStyle(tint: IslandPalette.accent.opacity(0.6)))
        }
    }

    private var dayContent: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.headline)
                    Text("Следующие 7 дней")
                        .font(.caption)
                        .foregroundStyle(IslandPalette.secondary)
                }
                Spacer()
                Button(action: service.load) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(RoundIconButtonStyle())
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("События", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 7) {
                            if service.events.isEmpty {
                                Text("Ближайших событий нет")
                                    .font(.caption)
                                    .foregroundStyle(IslandPalette.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 80)
                            }
                            ForEach(service.events) { event in
                                EventRow(event: event)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .islandCard(padding: 12, cornerRadius: 18)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Напоминания", systemImage: "checklist")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 6) {
                        TextField("Новое напоминание", text: $reminderTitle)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 9)
                            .frame(height: 29)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
                            .onSubmit(addReminder)
                        Button(action: addReminder) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(RoundIconButtonStyle(size: 29))
                    }

                    HStack(spacing: 7) {
                        Toggle("Срок", isOn: $hasDueDate)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                        if hasDueDate {
                            DatePicker("", selection: $reminderDate)
                                .labelsHidden()
                                .controlSize(.small)
                        }
                    }
                    .font(.caption)

                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 7) {
                            if service.reminders.isEmpty {
                                Text("Запланированных напоминаний нет")
                                    .font(.caption)
                                    .foregroundStyle(IslandPalette.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 55)
                            }
                            ForEach(service.reminders) { reminder in
                                ReminderRow(reminder: reminder) {
                                    service.complete(reminder)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .islandCard(padding: 12, cornerRadius: 18)
            }
        }
    }

    private func addReminder() {
        service.addReminder(title: reminderTitle, dueDate: hasDueDate ? reminderDate : nil)
        reminderTitle = ""
    }
}

private struct EventRow: View {
    let event: DayEvent

    var body: some View {
        HStack(spacing: 9) {
            Capsule()
                .fill(Color(nsColor: event.color))
                .frame(width: 3, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Text(event.isAllDay ? "Весь день" : event.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(IslandPalette.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }
}

private struct ReminderRow: View {
    let reminder: DayReminder
    let complete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: complete) {
                Image(systemName: "circle")
                    .foregroundStyle(IslandPalette.mint)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                if let due = reminder.dueDate {
                    Text(due.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(IslandPalette.secondary)
                }
            }
            Spacer()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }
}
