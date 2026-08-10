import Foundation

/// One selectable row in the Actions panel.
public struct ActionTemplate: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Selecting it produces a finished action with nothing left to fill in.
        case ready(ActionConfig)
        /// Selecting it reveals an inline editor — a shortcut recorder, a text
        /// field — before the action is complete.
        case needsInput(ActionType)
    }

    public let id: String
    public let title: String
    public let subtitle: String?
    public let symbolName: String
    public let kind: Kind

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        symbolName: String,
        kind: Kind
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.kind = kind
    }

    /// Whether this template is the one currently bound.
    ///
    /// Templates that need input match on action *type* alone, so the
    /// "Keyboard shortcut" row stays selected while the user is still choosing
    /// which shortcut.
    public func matches(_ action: ActionConfig) -> Bool {
        switch kind {
        case .ready(let template):
            if template.type == .preset {
                return action.type == .preset && action.preset == template.preset
            }
            return action.type == template.type
        case .needsInput(let type):
            return action.type == type
        }
    }
}

/// A named group of templates in the Actions panel.
public struct ActionSection: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let templates: [ActionTemplate]
    /// Whether the section starts expanded.
    public let isExpandedByDefault: Bool

    public init(
        id: String,
        title: String,
        templates: [ActionTemplate],
        isExpandedByDefault: Bool = true
    ) {
        self.id = id
        self.title = title
        self.templates = templates
        self.isExpandedByDefault = isExpandedByDefault
    }
}

/// The action library shown in the right-hand panel.
///
/// Kept in `MagicBindCore` rather than the view layer so the catalog can be
/// tested — in particular that every template resolves to an action
/// `ActionExecutor` can actually run.
public enum ActionCatalog {
    /// Actions that make sense for most people, listed first.
    public static let recommended = ActionSection(
        id: "recommended",
        title: "Recommended",
        templates: [
            ActionTemplate(
                id: "middleClick",
                title: "Middle Click",
                subtitle: "Wheel button click",
                symbolName: ActionType.middleClick.symbolName,
                kind: .ready(ActionConfig(type: .middleClick))
            ),
            template(for: .missionControl),
            template(for: .screenCaptureRegion),
            template(for: .desktopLeft),
            template(for: .desktopRight),
            ActionTemplate(
                id: "keyboardShortcut",
                title: "Keyboard Shortcut",
                subtitle: "Press a key combination to assign",
                symbolName: ActionType.keyboardShortcut.symbolName,
                kind: .needsInput(.keyboardShortcut)
            )
        ]
    )

    /// Window, space and system actions.
    public static let system = ActionSection(
        id: "system",
        title: "System Actions",
        templates: [
            template(for: .applicationWindows),
            template(for: .showDesktop),
            template(for: .fullScreen),
            template(for: .switchApplication),
            template(for: .screenCapture),
            template(for: .lockScreen)
        ],
        isExpandedByDefault: false
    )

    /// Editing, navigation and media.
    public static let other = ActionSection(
        id: "other",
        title: "Other Actions",
        templates: [
            template(for: .copy),
            template(for: .paste),
            template(for: .cut),
            template(for: .undo),
            template(for: .redo),
            template(for: .back),
            template(for: .forward),
            template(for: .volumeUp),
            template(for: .volumeDown),
            template(for: .mute),
            ActionTemplate(
                id: "launchApp",
                title: "Launch App",
                subtitle: "Open an application by bundle identifier",
                symbolName: ActionType.launchApp.symbolName,
                kind: .needsInput(.launchApp)
            ),
            ActionTemplate(
                id: "shellCommand",
                title: "Shell Command",
                subtitle: "Run a command with /bin/sh",
                symbolName: ActionType.shellCommand.symbolName,
                kind: .needsInput(.shellCommand)
            ),
            ActionTemplate(
                id: "appleScript",
                title: "AppleScript",
                subtitle: "Run a script",
                symbolName: ActionType.appleScript.symbolName,
                kind: .needsInput(.appleScript)
            )
        ],
        isExpandedByDefault: false
    )

    public static let sections = [recommended, system, other]

    /// Every template across every section.
    public static var allTemplates: [ActionTemplate] {
        sections.flatMap(\.templates)
    }

    /// Filters the catalog by a search string, dropping empty sections.
    ///
    /// An empty or whitespace-only query returns the catalog unchanged, with
    /// each section's default expansion preserved.
    public static func sections(matching query: String) -> [ActionSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sections }

        return sections.compactMap { section in
            let hits = section.templates.filter { $0.matches(query: trimmed) }
            guard !hits.isEmpty else { return nil }
            // Searching implies wanting to see the results, so matched sections
            // come back expanded regardless of their default.
            return ActionSection(
                id: section.id,
                title: section.title,
                templates: hits,
                isExpandedByDefault: true
            )
        }
    }

    /// The template matching an existing binding's action, if any.
    public static func template(matching action: ActionConfig) -> ActionTemplate? {
        allTemplates.first { $0.matches(action) }
    }

    private static func template(for preset: PresetAction) -> ActionTemplate {
        ActionTemplate(
            id: preset.rawValue,
            title: preset.displayName,
            subtitle: preset.shortcutDisplayString,
            symbolName: preset.symbolName,
            kind: .ready(preset.actionConfig)
        )
    }
}

extension ActionTemplate {
    /// Case- and diacritic-insensitive match against the title and subtitle.
    func matches(query: String) -> Bool {
        let haystack = [title, subtitle ?? ""].joined(separator: " ")
        return haystack.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }
}
