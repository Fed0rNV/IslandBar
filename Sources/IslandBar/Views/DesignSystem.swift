import AppKit
import SwiftUI

enum IslandPalette {
    static let background = Color(red: 0.025, green: 0.028, blue: 0.038)
    static let surface = Color.white.opacity(0.075)
    static let surfaceStrong = Color.white.opacity(0.12)
    static let stroke = Color.white.opacity(0.11)
    static let secondary = Color.white.opacity(0.62)
    static let accent = Color(red: 0.43, green: 0.55, blue: 1)
    static let purple = Color(red: 0.72, green: 0.42, blue: 1)
    static let mint = Color(red: 0.25, green: 0.9, blue: 0.72)
}

struct IslandCardModifier: ViewModifier {
    var padding: CGFloat = 14
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(IslandPalette.surface)
            )
    }
}

extension View {
    func islandCard(padding: CGFloat = 14, cornerRadius: CGFloat = 18) -> some View {
        modifier(IslandCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}

struct IslandButtonStyle: ButtonStyle {
    var tint: Color = IslandPalette.surfaceStrong

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(configuration.isPressed ? tint.opacity(0.65) : tint)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct RoundIconButtonStyle: ButtonStyle {
    var size: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(Circle().fill(configuration.isPressed ? Color.white.opacity(0.2) : Color.white.opacity(0.1)))
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

struct TopAttachedSurfaceShape: Shape {
    var bottomRadius: CGFloat
    let hasPhysicalNotch: Bool

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard hasPhysicalNotch else {
            return RoundedRectangle(
                cornerRadius: min(bottomRadius, rect.height / 2),
                style: .continuous
            ).path(in: rect)
        }

        let radius = min(max(bottomRadius, 0), rect.width / 2, rect.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

struct WaveBars: View {
    var active: Bool
    var color: Color = IslandPalette.mint
    var secondaryColor: Color? = nil
    var barCount = 4
    var barWidth: CGFloat = 2.5
    var maximumHeight: CGFloat = 18

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !active)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let offset = Double(index) * 1.37
                    let primaryWave = (sin(phase * (3.9 + Double(index) * 0.17) + offset) + 1) / 2
                    let secondaryWave = (sin(phase * 2.1 + offset * 0.72) + 1) / 2
                    let energy = active ? 0.22 + primaryWave * 0.54 + secondaryWave * 0.24 : 0.24
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [secondaryColor ?? color.opacity(0.78), color],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: barWidth, height: maximumHeight)
                        .scaleEffect(y: energy, anchor: .bottom)
                }
            }
        }
        .frame(height: maximumHeight)
        .drawingGroup(opaque: false, colorMode: .linear)
        .animation(.easeInOut(duration: 0.4), value: active)
        .animation(.easeInOut(duration: 0.4), value: color)
    }
}

struct MediaArtworkView: View {
    let image: NSImage?
    let primary: Color
    let secondary: Color
    var cornerRadius: CGFloat = 12

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [primary, secondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let maximum = max(values.max() ?? 1, 1)
            Path { path in
                guard values.count > 1 else { return }
                for (index, value) in values.enumerated() {
                    let x = proxy.size.width * CGFloat(index) / CGFloat(values.count - 1)
                    let y = proxy.size.height * (1 - CGFloat(value / maximum))
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(
                LinearGradient(colors: [color.opacity(0.4), color], startPoint: .leading, endPoint: .trailing),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(IslandPalette.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(IslandPalette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
