import AppKit
import Carbon.HIToolbox
import MagicBindCore
import SwiftUI

/// A "click to record" keyboard shortcut field.
///
/// Capture goes through `KeyCaptureTap` — a CGEvent tap that is armed only
/// while recording. Two earlier approaches each failed on a different class of
/// shortcut:
///
/// - `NSEvent.addLocalMonitorForEvents` never saw menu key equivalents (⌘W, ⌘Q).
/// - A first-responder `NSView` overriding `performKeyEquivalent(with:)` fixed
///   those but still missed system-reserved combinations such as the screenshot
///   shortcuts, and depended on the view actually being first responder.
///
/// The tap sits above both and is independent of focus. The responder-chain
/// path is kept as a fallback for when the tap can't be created — that only
/// happens without Accessibility permission, in which case the field still
/// records ordinary shortcuts.
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

    /// The AppKit view that draws the field and owns the capture tap.
    final class RecorderView: NSView {
        var onCapture: ((UInt16, UInt64?) -> Void)?
        var onClear: (() -> Void)?
        var onRecordingChanged: ((Bool) -> Void)?

        private var capture: KeyCaptureTap?
        /// True when the tap couldn't be created and we're relying on the
        /// responder chain, which can't see reserved shortcuts.
        private var isUsingFallback = false

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

        deinit {
            capture?.stop()
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: 32)
        }

        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { true }

        override func mouseDown(with event: NSEvent) {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }

        override func resignFirstResponder() -> Bool {
            // Clicking elsewhere disarms, rather than leaving a tap installed
            // and the keyboard swallowed.
            stopRecording()
            return super.resignFirstResponder()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { stopRecording() }
        }

        // MARK: - Recording

        private func startRecording() {
            guard !isRecording else { return }
            window?.makeFirstResponder(self)
            liveModifiers = []
            isRecording = true

            let tap = KeyCaptureTap(
                onModifiers: { [weak self] modifiers in
                    // Tap callbacks arrive on the main run loop, but hop anyway
                    // so UI mutation is unambiguously on the main thread.
                    DispatchQueue.main.async { self?.liveModifiers = modifiers }
                },
                onKey: { [weak self] keyCode, modifiers in
                    DispatchQueue.main.async { self?.handleCapturedKey(keyCode, modifiers) }
                }
            )

            do {
                try tap.start()
                capture = tap
                isUsingFallback = false
            } catch {
                // No Accessibility permission. Ordinary shortcuts still record
                // through the responder chain; reserved ones won't.
                capture = nil
                isUsingFallback = true
            }

            updateLabelForRecording()
            updateAppearance()
        }

        private func stopRecording() {
            guard isRecording else { return }
            isRecording = false
            capture?.stop()
            capture = nil
            isUsingFallback = false
            liveModifiers = []
            label.stringValue = shortcutText
            updateAppearance()
        }

        private func handleCapturedKey(_ keyCode: UInt16, _ modifiers: ShortcutModifiers) {
            guard isRecording else { return }

            // Escape and Delete are control keys only when pressed bare; with a
            // modifier held they're legitimate shortcuts (⌘⌫, ⌥⎋).
            if modifiers.isEmpty, keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return
            }
            if modifiers.isEmpty, keyCode == UInt16(kVK_Delete) {
                onClear?()
                stopRecording()
                return
            }

            onCapture?(keyCode, modifiers.isEmpty ? nil : modifiers.rawValue)
            stopRecording()
        }

        // MARK: - Responder-chain fallback

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording, isUsingFallback else { return false }
            handleCapturedKey(event.keyCode, Self.modifiers(from: event))
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording, isUsingFallback else {
                super.keyDown(with: event)
                return
            }
            handleCapturedKey(event.keyCode, Self.modifiers(from: event))
        }

        override func flagsChanged(with event: NSEvent) {
            guard isRecording, isUsingFallback else {
                super.flagsChanged(with: event)
                return
            }
            liveModifiers = Self.modifiers(from: event)
        }

        private static func modifiers(from event: NSEvent) -> ShortcutModifiers {
            ShortcutModifiers(rawValue: UInt64(event.modifierFlags.rawValue))
                .intersection(.displayable)
        }

        // MARK: - Appearance

        private func updateLabelForRecording() {
            guard isRecording else { return }
            if liveModifiers.isEmpty {
                label.stringValue = isUsingFallback
                    ? "Press a shortcut… (no Accessibility: ⌘⇧4 etc. won't record)"
                    : "Press a shortcut…"
            } else {
                label.stringValue = liveModifiers.glyphs + "…"
            }
        }

        /// Layer colours are resolved in `updateLayer()`, never at configuration
        /// time.
        ///
        /// `NSColor.controlBackgroundColor.cgColor` collapses a *dynamic* colour
        /// into a fixed one using whatever appearance happens to be current when
        /// the conversion runs — which, from `init` or a state-change method, is
        /// not the view's appearance. That baked light-mode values in, so in dark
        /// mode the field drew a white box with white text and the recorded
        /// shortcut was invisible.
        ///
        /// Resolving inside `performAsCurrentDrawingAppearance` binds the
        /// conversion to this view's effective appearance, and
        /// `viewDidChangeEffectiveAppearance` re-runs it when the user switches
        /// theme while the window is open.
        override var wantsUpdateLayer: Bool { true }

        override func updateLayer() {
            super.updateLayer()
            effectiveAppearance.performAsCurrentDrawingAppearance { [self] in
                layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
                layer?.borderColor = isRecording
                    ? NSColor.controlAccentColor.cgColor
                    : NSColor.separatorColor.cgColor
            }
            layer?.borderWidth = isRecording ? 2 : 1
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }

        private func updateAppearance() {
            // NSTextField resolves a dynamic NSColor at draw time by itself, so
            // the text colour is safe to set here; only CGColor conversion is not.
            label.textColor = isRecording ? .controlAccentColor : .labelColor
            needsDisplay = true
        }
    }
}
