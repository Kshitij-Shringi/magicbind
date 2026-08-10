import Foundation
import MagicBindCore
import SwiftUI

/// The window: device canvas on the left, Actions panel on the right.
struct MainWindowView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            canvas
            Divider().overlay(Theme.hairline)
            ActionsPanelView()
        }
        .background(Theme.canvasBackground)
        // The device illustration and palette are drawn for a dark background,
        // so the window commits to dark rather than adapting.
        .preferredColorScheme(.dark)
    }

    private var canvas: some View {
        VStack(spacing: 0) {
            toolbar

            ZStack {
                switch state.screen {
                case .device:
                    DeviceScreen()
                case .customGestures:
                    CustomGesturesScreen()
                case .settings:
                    TuningSettingsScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .frame(minWidth: 640)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button {
                state.screen = .device
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(
                        state.screen == .device ? Theme.secondaryText : Theme.primaryText
                    )
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state.screen == .device)
            .help("Back to the device overview")

            if state.screen != .device {
                Text(state.screen.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .padding(.leading, 6)
            }

            Spacer()

            HStack(spacing: 4) {
                toolbarTab(.device, symbol: "circle.grid.2x2")
                toolbarTab(.customGestures, symbol: "arrow.up.arrow.down.circle")
                toolbarTab(.settings, symbol: "slider.horizontal.3")

                Button {
                    state.addBinding()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add a gesture")
            }

            Spacer()

            // Balances the leading back button so the tabs stay centered.
            Color.clear.frame(width: 30, height: 30)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func toolbarTab(_ screen: AppScreen, symbol: String) -> some View {
        let isActive = state.screen == screen
        return Button {
            state.screen = screen
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isActive ? Theme.accent : Theme.secondaryText)
                .frame(width: 34, height: 30)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isActive ? Theme.accent : Color.clear)
                        .frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(screen.title)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            StatusBadge()

            if let message = state.lastErrorMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.danger)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if let gesture = state.lastGesture {
                Text("Last: \(gesture.displayName)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .padding(.top, 8)
    }
}

/// ACTIVE / INACTIVE, matching the badge position in Logi Options+.
struct StatusBadge: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let isLive = state.isEngineRunning && state.config.isEnabled

        return Button {
            state.toggleEnabled()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isLive ? Theme.statusActive : Theme.statusInactive)
                    .frame(width: 6, height: 6)
                Text(isLive ? "ACTIVE" : "INACTIVE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(isLive ? Theme.primaryText : Theme.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isLive ? "Click to disable gestures" : "Click to enable gestures")
    }
}

/// The overview: the device with every non-swipe binding arranged around it.
struct DeviceScreen: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let bindings = state.overviewBindings

            ZStack {
                DeviceIllustration(
                    fingerCount: state.selectedBinding?.gesture.fingerCount ?? 0,
                    showsClick: state.selectedBinding?.gesture.kind == .click
                )
                .frame(width: 168, height: 330)
                .position(center)

                ForEach(Array(bindings.enumerated()), id: \.element.id) { index, binding in
                    let offset = Self.chipOffset(
                        index: index,
                        total: bindings.count,
                        size: proxy.size
                    )
                    BindingChip(
                        binding: binding,
                        isSelected: state.selectedBindingID == binding.id
                    ) {
                        state.selectedBindingID = binding.id
                    }
                    .position(x: center.x + offset.x, y: center.y + offset.y)
                }

                if bindings.isEmpty {
                    Text("No gestures yet — add one with +.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .position(x: center.x, y: proxy.size.height - 40)
                }
            }
        }
    }

    /// Distributes chips around an ellipse, starting at the upper right and
    /// going clockwise, skipping the very top and bottom so nothing lands on
    /// the device's nose or tail.
    static func chipOffset(index: Int, total: Int, size: CGSize) -> CGPoint {
        guard total > 0 else { return .zero }

        let radiusX = max(190, size.width * 0.33)
        let radiusY = max(120, size.height * 0.32)

        // Spread over 300° rather than 360° to leave the top clear.
        let sweep = 300.0
        let step = total == 1 ? 0 : sweep / Double(total - 1)
        let angle = Angle(degrees: -150 + step * Double(index) + 90).radians

        return CGPoint(
            x: Darwin.cos(angle) * radiusX,
            y: Darwin.sin(angle) * radiusY
        )
    }
}
