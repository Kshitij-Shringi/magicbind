import Foundation

/// Wires the pipeline together: raw frames in, bound actions out.
///
/// ```
/// MultitouchReader -> GestureRecognizer -> ConfigStore lookup -> ActionExecutor
/// ```
///
/// The engine owns the reader and recognizer; the config store is injected so
/// the preferences UI and the engine share one source of truth.
public final class GestureEngine {
    private let store: ConfigStore
    private let executor: ActionExecutor
    private let recognizer: GestureRecognizer
    private var reader: MultitouchReader?
    private var buttonMonitor: MouseButtonMonitor?

    /// Monotonic clock for button events, which arrive without the timestamp
    /// the touch frames carry.
    private static var now: Double {
        ProcessInfo.processInfo.systemUptime
    }

    /// Whether physical buttons are currently being watched.
    public var isWatchingMouseButtons: Bool {
        buttonMonitor?.isRunning ?? false
    }

    /// Called whenever an action fails, on the main queue. The app uses this
    /// to surface a notification instead of failing silently.
    public var errorHandler: ((Error) -> Void)?

    /// Called whenever a gesture is recognized, on the main queue, whether or
    /// not it matched a binding. Useful for the diagnostics window.
    public var gestureHandler: ((GestureSpec) -> Void)?

    public private(set) var isRunning = false

    public init(store: ConfigStore, executor: ActionExecutor = ActionExecutor()) {
        self.store = store
        self.executor = executor
        self.recognizer = GestureRecognizer(tuning: store.config.tuning)
    }

    /// Starts reading the device and dispatching gestures.
    public func start() throws {
        guard !isRunning else { return }

        recognizer.tuning = store.config.tuning
        recognizer.reset()

        let reader = MultitouchReader { [weak self] fingers, timestamp in
            self?.handleFrame(fingers: fingers, timestamp: timestamp)
        }
        try reader.start()

        self.reader = reader
        isRunning = true

        // A failure here shouldn't take the whole engine down: touch gestures
        // still work without click support, so the error is surfaced and the
        // rest keeps running.
        if store.config.isMouseClicksEnabled {
            do {
                try startButtonMonitor()
            } catch {
                errorHandler?(error)
            }
        }
    }

    public func stop() {
        guard isRunning else { return }
        reader?.stopReading()
        reader = nil
        stopButtonMonitor()
        recognizer.reset()
        isRunning = false
    }

    /// Picks up threshold changes made in preferences without a restart.
    public func reloadTuning() {
        recognizer.tuning = store.config.tuning
    }

    /// Starts or stops the button tap to match `mouseClicksEnabled`, so the
    /// toggle takes effect without restarting the engine.
    public func syncMouseButtonWatching() {
        guard isRunning else { return }

        let wanted = store.config.isMouseClicksEnabled
        if wanted && buttonMonitor == nil {
            do {
                try startButtonMonitor()
            } catch {
                errorHandler?(error)
            }
        } else if !wanted {
            stopButtonMonitor()
        }
    }

    private func startButtonMonitor() throws {
        guard buttonMonitor == nil else { return }

        if !MouseButtonMonitor.isPermitted {
            MouseButtonMonitor.requestPermission()
        }

        let monitor = MouseButtonMonitor { [weak self] button, isDown in
            self?.handleButton(button, isDown: isDown)
        }
        try monitor.start()
        buttonMonitor = monitor
    }

    private func stopButtonMonitor() {
        buttonMonitor?.stop()
        buttonMonitor = nil
    }

    /// Button events arrive on the main run loop, since that's where the tap
    /// was added, so this is already main-queue work.
    private func handleButton(_ button: MouseButton, isDown: Bool) {
        guard store.config.isEnabled else { return }
        guard
            let gesture = recognizer.processButton(button, isDown: isDown, timestamp: Self.now)
        else { return }

        dispatch(gesture)
    }

    /// Frames arrive on the framework's callback thread. Classification is
    /// cheap and thread-confined to that thread; anything that touches AppKit
    /// or user-visible state hops to the main queue.
    private func handleFrame(fingers: [MTFinger], timestamp: Double) {
        guard store.config.isEnabled else { return }
        guard let gesture = recognizer.process(fingers: fingers, timestamp: timestamp) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.dispatch(gesture)
        }
    }

    private func dispatch(_ gesture: GestureSpec) {
        gestureHandler?(gesture)

        guard let binding = store.config.binding(for: gesture) else { return }

        do {
            try executor.perform(binding.action)
        } catch {
            errorHandler?(error)
        }
    }
}
