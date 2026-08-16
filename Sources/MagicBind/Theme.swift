import SwiftUI

/// Layout metrics only.
///
/// There is deliberately no colour palette here. An earlier version forced a
/// dark theme with hardcoded colours, which looked foreign next to every other
/// Mac app and ignored the user's system appearance. Views now use semantic
/// colours (`.primary`, `.secondary`, `Color.accentColor`, and the standard
/// control materials), so light and dark both come for free.
enum Metrics {
    static let sidebarMinWidth: CGFloat = 240
    static let sidebarIdealWidth: CGFloat = 270
    static let detailMinWidth: CGFloat = 460
    static let windowMinWidth: CGFloat = 760
    static let windowMinHeight: CGFloat = 520
    static let cornerRadius: CGFloat = 6
}
