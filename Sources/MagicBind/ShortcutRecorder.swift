import AppKit
import Carbon.HIToolbox
import MagicBindCore
import SwiftUI

/// A shortcut recorder backed by a real first-responder `NSView`.
///
/// The first version used `NSEvent.addLocalMonitorForEvents`, which does not
/// reliably see **key equivalents** — ⌘W, ⌘Q, ⌘, and anything else claimed by
/// the main menu get consumed before a monitor sees them, so those shortcuts
/// silently failed to record. An `NSView` that becomes first responder and
/// overrides `performKeyEquivalent(with:)` sees them first, which is how every
/// working macOS shortcut recorder does it.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var keyCode: UInt16?
    @Binding var modifiers: UInt64?

    /// Called when recording starts or stops, so the surrounding row can show
    /// its armed state.
    var onRecordingChanged: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCapture = { code, mods in
            keyCode = code
            modifiers = mods
        }
        view.onClear = {
            keyCode = nil
            modifiers = nil
        }
        view.onRecordingChanged = onRecordingChanged
        view.shortcutText = displayText
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        // Don't stomp the "Press a shortcut…" prompt while the user is mid-press.
        guard !view.isRecording else { return }
        view.shortcutText = displayText
    }

    private var displayText: String {
        KeyboardShortcutFormatter.displayString(keyCode: keyCode, modifiers: modifiers)
            ?? "Click to record shortcut"
    }

    /// The AppKit view that does the actual capturing.
    final class RecorderView: NSView {
        var onCapture: ((UInt16, UInt64?) -> Void)?
        var onClear: (() -> Void)?
        var onRecordingChanged: ((Bool) -> Void)?

        private(set) var isRecording = false {
            didSet {
                guard isRecording != oldValue else { return }
                onRecordingChanged?(isRecording)
                needsDisplay = true
            }
        }

        var shortcutText: String = "" {
            didSet {
                guard shortcutText != oldValue else { return }
                label.stringValue = shortcutText
                needsDisplay = true
            }
        }

        private var liveModifiers = ShortcutModifiers() {
            didSet { updateLabelForRecording() }
        }

        private let label: NSTextField = {
            let field = NSTextField(labelWithString: "")
            field.alignment = .center
            field.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
            field.textColor = .white
            field.lineBreakMode = .byTruncatingTail
            return field
        }()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.cornerRadius = 6
            layer?.borderWidth = 1
            addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
            ])
            updateAppearance()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: 32)
        }

        // Being in the key view loop is what lets the view take first responder
        // status, and therefore receive key events at all.
        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { true }

        override func mouseDown(with event: NSEvent) {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            updateAppearance()
            return accepted
        }

        override func resignFirstResponder() -> Bool {
            // Clicking elsewhere should disarm, not leave the field silently
            // eating keystrokes.
            stopRecording()
            return super.resignFirstResponder()
        }

        private func startRecording() {
            window?.makeFirstResponder(self)
            liveModifiers = []
            isRecording = true
            updateLabelForRecording()
            updateAppearance()
        }

        private func stopRecording() {
            guard isRecording else { return }
            isRecording = false
            liveModifiers = []
            label.stringValue = shortcutText
            updateAppearance()
        }

        // MARK: - Key handling

        /// Key equivalents reach here before the menu bar can claim them, which
        /// is the whole reason this view exists.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording else { return false }
            return capture(event)
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording, capture(event) else {
                super.keyDown(with: event)
                return
            }
        }

        override func flagsChanged(with event: NSEvent) {
            guard isRecording else {
                super.flagsChanged(with: event)
                return
            }
            liveModifiers = Self.modifiers(from: event)
        }

        /// - Returns: whether the event was consumed.
        private func capture(_ event: NSEvent) -> Bool {
            let flags = Self.modifiers(from: event)

            // Escape and Delete are control keys only when pressed bare; with a
            // modifier held they're legitimate shortcuts (⌘⌫, ⌥⎋).
            if flags.isEmpty, event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return true
            }
            if flags.isEmpty, event.keyCode == UInt16(kVK_Delete) {
                onClear?()
                stopRecording()
                return true
            }

            onCapture?(event.keyCode, flags.isEmpty ? nil : flags.rawValue)
            stopRecording()
            return true
        }

        private static func modifiers(from event: NSEvent) -> ShortcutModifiers {
            ShortcutModifiers(rawValue: UInt64(event.modifierFlags.rawValue))
                .intersection(.displayable)
        }

        // MARK: - Appearance

        private func updateLabelForRecording() {
            guard isRecording else { return }
            label.stringValue = liveModifiers.isEmpty
                ? "Press a shortcut…"
                : liveModifiers.glyphs + "…"
        }

        private func updateAppearance() {
            let accent = NSColor(
                srgbRed: 0.36, green: 0.90, blue: 0.78, alpha: 1.0
            )
            layer?.backgroundColor = NSColor(white: 0.16, alpha: 1.0).cgColor
            layer?.borderColor = isRecording
                ? accent.cgColor
                : NSColor(white: 1.0, alpha: 0.12).cgColor
            layer?.borderWidth = isRecording ? 2 : 1
            label.textColor = isRecording ? accent : .white
        }
    }
}
