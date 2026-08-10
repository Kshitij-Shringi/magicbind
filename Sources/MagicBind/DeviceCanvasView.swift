import MagicBindCore
import SwiftUI

/// The silhouette of a Magic Mouse, drawn rather than photographed.
///
/// This is a vector illustration on purpose: Apple's product photography is
/// licensed, and an open-source repo shouldn't ship it. Two mirrored pairs of
/// cubic curves give the characteristic profile — narrow at the front, widest
/// just above the middle, rounded tail.
struct MagicMouseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let centerX = rect.midX
        let shoulderY = rect.minY + height * 0.42

        path.move(to: CGPoint(x: centerX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: shoulderY),
            control1: CGPoint(x: centerX + width * 0.30, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + height * 0.15)
        )
        path.addCurve(
            to: CGPoint(x: centerX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.minY + height * 0.80),
            control2: CGPoint(x: centerX + width * 0.36, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: shoulderY),
            control1: CGPoint(x: centerX - width * 0.36, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.minY + height * 0.80)
        )
        path.addCurve(
            to: CGPoint(x: centerX, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + height * 0.15),
            control2: CGPoint(x: centerX - width * 0.30, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// The device illustration, optionally showing where fingers would rest.
struct DeviceIllustration: View {
    /// How many finger indicators to draw on the touch surface.
    var fingerCount: Int = 0
    /// Whether to show the click indicator at the front of the shell.
    var showsClick: Bool = false

    var body: some View {
        MagicMouseShape()
            .fill(
                LinearGradient(
                    colors: [Theme.deviceTop, Theme.deviceBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                MagicMouseShape()
                    .stroke(Theme.deviceEdge, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                // The seam where the touch surface meets the shell.
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, 26)
                    .padding(.top, 96)
            }
            .overlay(alignment: .top) {
                if showsClick {
                    Circle()
                        .strokeBorder(Theme.accent, lineWidth: 2)
                        .frame(width: 26, height: 26)
                        .padding(.top, 40)
                }
            }
            .overlay(alignment: .top) {
                fingerIndicators
                    .padding(.top, 130)
            }
            .shadow(color: .black.opacity(0.6), radius: 30, y: 18)
    }

    /// Finger dots spread across the surface, so a "4-finger" binding is
    /// something you can see rather than just read.
    private var fingerIndicators: some View {
        HStack(spacing: 9) {
            ForEach(0..<max(0, min(fingerCount, 5)), id: \.self) { index in
                Circle()
                    .fill(Theme.accent.opacity(0.9))
                    .frame(width: 13, height: 13)
                    .overlay {
                        Circle().strokeBorder(Theme.onAccent.opacity(0.35), lineWidth: 1)
                    }
                    // Fan the dots slightly, the way fingers actually sit.
                    .offset(y: index == 0 || index == fingerCount - 1 ? 6 : 0)
            }
        }
    }
}

/// A binding label placed around the device, in the style of Logi Options+.
struct BindingChip: View {
    let binding: GestureBinding
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(binding.gesture.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.onAccent : Theme.primaryText)
                Text(binding.action.displaySummary)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        isSelected ? Theme.onAccent.opacity(0.75) : Theme.secondaryText
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: 190, alignment: .leading)
            .chipBackground(isSelected: isSelected)
            .opacity(binding.isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .help(
            binding.isEnabled
                ? binding.action.displaySummary
                : "Disabled — \(binding.action.displaySummary)"
        )
    }
}
