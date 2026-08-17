import Foundation

/// Wires the pipeline together: raw frames in, bound actions out.
///
/// ```
/// MultitouchReader -> GestureRecognizer -> ConfigStore lookup -> ActionExecutor
///                     (one per device)
/// ```
///
/// The engine owns the reader and the recognizers; the config store is injected
/// so the UI and the engine share one source of truth.
public final class GestureEngine {
    private let store: ConfigStore
    private let executor: ActionExecutor
    private var reader: MultitouchReader?
    private var buttonMonitor: MouseButtonMonitor?

    /// One recognizer per device.
    ///
    /// A Mac with both a Magic Mouse and a trackpad interleaves frames from
    /// both. Sharing a recognizer would let one device's touches start an
    /// episode the other device's touches then finish, producing gestures nobody
    /// made.
    private var recognizers: [UInt64: GestureRecognizer] = [:]

    /// Guards `recognizers` and `lastContactDeviceID`.
    ///
    /// Touch frames arrive on the framework's own callback thread while button
    /// events arrive on the main run loop, and both paths read and mutate this
    /// state. Without a lock that is a data race on a Swift Dictionary, which
    /// can corrupt recognizer state or crash outright — and it would present as
    /// gestures working intermittently, which is exactly the sort of bug that
    /// wastes hours.
    private let lock = NSLock()

    /// Which device most recently reported contact, so a physical click can be
    /// attributed to a device.
    ///
    /// `CGEvent` carries no device identity, so this is genuinely best-effort:
    /// a click with fingers resting on a device is attributed to that device,
    /// and a click with no contact anywhere is attributed to the first
    /// non-trackpad device. Documented in `docs/TESTING.md`.
    private var lastContactDeviceID: UInt64?

    /// Monotonic clock for button events, which arrive without the timestamp
    /// the touch frames carry.
    private static var now: Double {
        ProcessInfo.processInfo.systemUptime
    }

    /// Called whenever an action fails, on the main queue. The app uses this
    /// to surface a notification instead of failing silently.
    public var errorHandler: ((Error) -> Void)?

    /// Called whenever a gesture is recognized, on the main queue, whether or
    /// not it matched a binding. Drives the "last gesture" readout, which is the
    /// main diagnostic for whether the touch data works at all.
    public var gestureHandler: ((GestureSpec, MTDeviceInfo?) -> Void)?

    /// Called after the device list is known, on the main queue.
    public var devicesHandler: (([MTDeviceInfo]) -> Void)?

    public private(set) var isRunning = false

    /// Whether physical buttons are currently being watched.
    public var isWatchingMouseButtons: Bool {
        buttonMonitor?.isRunning ?? false
    }

    /// Every device the reader found, empty until `start()` succeeds.
    public var devices: [MTDeviceInfo] {
        reader?.devices ?? []
    }

    /// How many touch frames the reader has delivered. Zero while gestures are
    /// being made means the reader is broken, which is a very different problem
    /// from a threshold being wrong.
    public var frameCount: Int {
        reader?.frameCount ?? 0
    }

    public init(store: ConfigStore, executor: ActionExecutor = ActionExecutor()) {
        self.store = store
        self.executor = executor
    }

    /// Starts reading every device and dispatching gestures.
    public func start() throws {
        guard !isRunning else { return }

        lock.lock()
        recognizers = [:]
        lastContactDeviceID = nil
        lock.unlock()

        let reader = MultitouchReader { [weak self] device, fingers, timestamp in
            self?.handleFrame(device: device, fingers: fingers, timestamp: timestamp)
        }
        try reader.start()

        self.reader = reader
        isRunning = true

        let found = reader.devices
        DispatchQueue.main.async { [weak self] in
            self?.devicesHandler?(found)
        }

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
        lock.lock()
        recognizers = [:]
        lastContactDeviceID = nil
        lock.unlock()
        isRunning = false
    }

    /// Picks up threshold changes made in the UI without a restart.
    public func reloadTuning() {
        let tuning = store.config.tuning
        lock.lock()
        for recognizer in recognizers.values {
            recognizer.tuning = tuning
        }
        lock.unlock()
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

    // MARK: - Touch frames

    /// Frames arrive on the framework's callback thread. Classification is
    /// cheap and confined to that thread; anything user-visible hops to main.
    private func handleFrame(device: MTDeviceInfo, fingers: [MTFinger], timestamp: Double) {
        guard store.config.isEnabled else { return }

        // Disabled devices are dropped before recognition, so a switched-off
        // trackpad costs nothing and can't leave a half-finished session behind.
        guard store.config.isDeviceEnabled(device.kind) else { return }

        lock.lock()
        if fingers.contains(where: \.isContact) {
            lastContactDeviceID = device.deviceID
        }
        let gesture = recognizer(for: device).process(fingers: fingers, timestamp: timestamp)
        lock.unlock()

        guard let gesture else { return }

        DispatchQueue.main.async { [weak self] in
            self?.dispatch(gesture, from: device)
        }
    }

    /// - Important: callers must hold `lock`.
    private func recognizer(for device: MTDeviceInfo) -> GestureRecognizer {
        if let existing = recognizers[device.deviceID] {
            return existing
        }
        let created = GestureRecognizer(tuning: store.config.tuning)
        recognizers[device.deviceID] = created
        return created
    }

    // MARK: - Mouse buttons

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

    /// Button events arrive on the main run loop, since that's where the tap was
    /// added, so this is already main-queue work.
    private func handleButton(_ button: MouseButton, isDown: Bool) {
        guard store.config.isEnabled else { return }

        lock.lock()
        let device = clickDevice()
        if let device, !store.config.isDeviceEnabled(device.kind) {
            lock.unlock()
            return
        }
        let recognizer = device.map { self.recognizer(for: $0) } ?? fallbackRecognizer()
        let gesture = recognizer.processButton(button, isDown: isDown, timestamp: Self.now)
        lock.unlock()

        guard let gesture else { return }
        dispatch(gesture, from: device)
    }

    /// Best-effort attribution of a click to a device: whichever device last
    /// reported contact, else the first non-trackpad device.
    /// - Important: callers must hold `lock`.
    private func clickDevice() -> MTDeviceInfo? {
        let all = devices
        if let lastContactDeviceID,
           let match = all.first(where: { $0.deviceID == lastContactDeviceID }) {
            return match
        }
        return all.first { !$0.kind.isTrackpad } ?? all.first
    }

    /// Used when no device is known — a click before any touch has been seen.
    /// Keyed on zero so it can't collide with a real device ID.
    /// - Important: callers must hold `lock`.
    private func fallbackRecognizer() -> GestureRecognizer {
        if let existing = recognizers[0] { return existing }
        let created = GestureRecognizer(tuning: store.config.tuning)
        recognizers[0] = created
        return created
    }

    // MARK: - Dispatch

    private func dispatch(_ gesture: GestureSpec, from device: MTDeviceInfo?) {
        gestureHandler?(gesture, device)

        let binding: GestureBinding?
        if let kind = device?.kind {
            binding = store.config.binding(for: gesture, on: kind)
        } else {
            binding = store.config.binding(for: gesture)
        }
        guard let binding else { return }

        do {
            try executor.perform(binding.action)
        } catch {
            errorHandler?(error)
        }
    }
}
