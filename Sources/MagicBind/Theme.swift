import SwiftUI

/// The dark palette and metrics the whole window is built from.
///
/// Kept in one place so the Actions panel, the device canvas, and the gesture
/// screens can't drift apart. The window forces dark mode rather than adapting,
/// because the device illustration is drawn for a dark background.
enum Theme {
    // MARK: - Colors

    /// The window background behind the device canvas.
    static let canvasBackground = Color(red: 0.04, green: 0.04, blue: 0.05)

    /// The Actions panel background.
    static let panelBackground = Color(red: 0.02, green: 0.02, blue: 0.02)

    /// The panel header, one step lighter than the panel itself.
    static let panelHeader = Color(red: 0.07, green: 0.07, blue: 0.08)

    /// Chips, search fields, and inactive rows.
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.12)

    /// A raised surface, used for the inline editor inside a selected row.
    static let surfaceRaised = Color(red: 0.16, green: 0.16, blue: 0.17)

    /// The mint accent. Selected rows use it as a background with dark text.
    static let accent = Color(red: 0.36, green: 0.90, blue: 0.78)

    /// Text on top of the accent color.
    static let onAccent = Color(red: 0.02, green: 0.06, blue: 0.05)

    static let primaryText = Color.white
    static let secondaryText = Color(white: 0.58)
    static let hairline = Color(white: 1.0, opacity: 0.08)

    static let statusActive = Color(red: 0.36, green: 0.90, blue: 0.78)
    static let statusInactive = Color(white: 0.35)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.38)

    // MARK: - Device illustration

    static let deviceTop = Color(red: 0.27, green: 0.28, blue: 0.30)
    static let deviceBottom = Color(red: 0.09, green: 0.09, blue: 0.10)
    static let deviceEdge = Color(white: 1.0, opacity: 0.16)

    // MARK: - Metrics

    static let panelWidth: CGFloat = 380
    static let cornerRadius: CGFloat = 8
    static let chipCornerRadius: CGFloat = 6
}

extension View {
    /// A chip: the dark rounded label used for bindings around the device.
    func chipBackground(isSelected: Bool) -> some View {
        background(
            RoundedRectangle(cornerRadius: Theme.chipCornerRadius)
                .fill(isSelected ? Theme.accent : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.chipCornerRadius)
                .strokeBorder(isSelected ? Color.clear : Theme.hairline)
        )
    }
}
