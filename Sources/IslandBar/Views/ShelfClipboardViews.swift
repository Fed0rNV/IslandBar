import AppKit
import SwiftUI

struct ShelfView: View {
    @ObservedObject var state: AppState

    private let columns = [GridItem(.adaptive(minimum: 138, maximum: 190), spacing: 10)]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Файловая полка")
                        .font(.headline)
                    Text("Перетащите сюда файлы, а потом вытяните их в другое приложение")
                        .font(.caption)
                        .foregroundStyle(IslandPalette.secondary)
                }
                Spacer()
                if !state.shelfItems.isEmpty {
                    Button {
                        state.shareByAirDrop(state.shelfItems)
                    } label: {
                        Label("AirDrop", systemImage: "airplayaudio")
                    }
                    .buttonStyle(IslandButtonStyle())

                    Button {
                        state.clearShelf()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(RoundIconButtonStyle())
                    .help("Очистить полку — сами файлы не удаляются")
                }
                Button(action: state.chooseFiles) {
                    Label("Добавить", systemImage: "plus")
                }
                .buttonStyle(IslandButtonStyle(tint: IslandPalette.accent.opacity(0.55)))
            }

            if state.shelfItems.isEmpty {
                Button(action: state.chooseFiles) {
                    VStack(spacing: 12) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(IslandPalette.accent)
                        Text("Бросьте файлы в островок")
                            .font(.headline)
                        Text("IslandBar хранит ссылки на них — без копий и без загрузки в облако")
                            .font(.caption)
                            .foregroundStyle(IslandPalette.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(0.035))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(IslandPalette.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                            )
                    )
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(state.shelfItems) { item in
                            ShelfItemView(item: item, state: state)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }
}

private struct ShelfItemView: View {
    let item: ShelfItem
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 38, height: 38)
                    .opacity(item.exists ? 1 : 0.4)
                Spacer()
                Menu {
                    Button("Открыть", action: { state.open(item) })
                    Button("Показать в Finder", action: { state.reveal(item) })
                    Button("Отправить через AirDrop", action: { state.shareByAirDrop([item]) })
                    Divider()
                    Button("Убрать с полки", role: .destructive, action: { state.removeShelfItem(item) })
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 25, height: 22)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Text(item.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.detail)
                .font(.caption2)
                .foregroundStyle(item.exists ? IslandPalette.secondary : .red)
        }
        .islandCard(padding: 11, cornerRadius: 15)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { state.open(item) }
        .onDrag {
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider(object: item.url as NSURL)
        }
        .contextMenu {
            Button("Открыть", action: { state.open(item) })
            Button("Показать в Finder", action: { state.reveal(item) })
            Button("AirDrop", action: { state.shareByAirDrop([item]) })
            Divider()
            Button("Убрать с полки", action: { state.removeShelfItem(item) })
        }
    }
}

struct ClipboardView: View {
    @ObservedObject var monitor: ClipboardMonitor

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("История буфера")
                        .font(.headline)
                    Text("Только в памяти; пароли с меткой Concealed не записываются")
                        .font(.caption)
                        .foregroundStyle(IslandPalette.secondary)
                }
                Spacer()
                Toggle("Следить", isOn: $monitor.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                if !monitor.entries.isEmpty {
                    Button(action: monitor.clear) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(RoundIconButtonStyle())
                    .help("Очистить историю")
                }
            }

            if monitor.entries.isEmpty {
                EmptyStateView(
                    symbol: "doc.on.clipboard",
                    title: monitor.isEnabled ? "Скопируйте что-нибудь" : "Отслеживание выключено",
                    detail: monitor.isEnabled
                        ? "Здесь появятся тексты, изображения и файлы из буфера обмена"
                        : "Включите переключатель, чтобы собирать историю текущего сеанса"
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(monitor.entries) { entry in
                            ClipboardRow(entry: entry, monitor: monitor)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    @ObservedObject var monitor: ClipboardMonitor

    var body: some View {
        HStack(spacing: 12) {
            preview
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.075)))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(entry.capturedAt.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(IslandPalette.secondary)
            }
            Spacer()
            Button {
                monitor.copy(entry)
            } label: {
                Label("Вернуть", systemImage: "doc.on.clipboard.fill")
            }
            .buttonStyle(IslandButtonStyle())
            Button {
                monitor.remove(entry)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(RoundIconButtonStyle(size: 30))
        }
        .islandCard(padding: 10, cornerRadius: 14)
        .contentShape(Rectangle())
        .onTapGesture { monitor.copy(entry) }
    }

    @ViewBuilder
    private var preview: some View {
        if let data = entry.imageData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: entry.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(IslandPalette.accent)
        }
    }
}
