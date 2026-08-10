import CoreFoundation
import Foundation

/// An opaque handle to a multitouch device.
public typealias MTDeviceRef = UnsafeMutableRawPointer

/// The C callback the private framework invokes for every contact frame.
///
/// The finger buffer is typed as a raw pointer because `@convention(c)`
/// signatures may only mention C-representable types, and `MTFinger` is a
/// Swift struct. It is bound to `MTFinger` inside the callback.
private typealias MTContactCallback = @convention(c) (
    MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32
) -> Int32

private typealias MTDeviceCreateListFn = @convention(c) () -> Unmanaged<CFMutableArray>?
private typealias MTRegisterCallbackFn = @convention(c) (MTDeviceRef, MTContactCallback) -> Void
private typealias MTUnregisterCallbackFn = @convention(c) (MTDeviceRef, MTContactCallback) -> Void
private typealias MTDeviceStartFn = @convention(c) (MTDeviceRef, Int32) -> Void
private typealias MTDeviceStopFn = @convention(c) (MTDeviceRef) -> Void

/// The single reader the C callback forwards frames to.
///
/// `@convention(c)` function pointers cannot capture context, so the callback
/// has to reach its reader through a global. Only one `MultitouchReader` can
/// be started at a time, which is enforced in `start()`.
private var activeReader: MultitouchReader?

/// The trampoline registered with the private framework. Converts the raw
/// finger buffer into a Swift array and hands it to the active reader.
private func magicBindContactFrameCallback(
    device: MTDeviceRef?,
    fingers: UnsafeMutableRawPointer?,
    count: Int32,
    timestamp: Double,
    frame: Int32
) -> Int32 {
    guard let reader = activeReader else { return 0 }

    var frameFingers: [MTFinger] = []
    if let fingers, count > 0 {
        let typed = fingers.bindMemory(to: MTFinger.self, capacity: Int(count))
        frameFingers = Array(UnsafeBufferPointer(start: typed, count: Int(count)))
    }
    reader.deliver(fingers: frameFingers, timestamp: timestamp)
    return 0
}

/// Reads raw touch frames from Apple's private
/// `MultitouchSupport.framework`.
///
/// - Warning: This framework is private and undocumented. It is resolved at
///   runtime with `dlopen`/`dlsym` rather than linked, so a macOS update that
///   removes or renames a symbol degrades to "no gestures" instead of a crash
///   on launch. Every symbol lookup that fails is reported through
///   `ReaderError`. See `SECURITY.md` for the risk discussion.
public final class MultitouchReader {
    public enum ReaderError: Error, LocalizedError {
        case frameworkUnavailable(String)
        case symbolUnavailable(String)
        case noDevices
        case alreadyRunning

        public var errorDescription: String? {
            switch self {
            case .frameworkUnavailable(let path):
                return "Could not load MultitouchSupport.framework at \(path)."
            case .symbolUnavailable(let symbol):
                return "MultitouchSupport.framework has no symbol named \(symbol)."
            case .noDevices:
                return "No multitouch devices found. Is the Magic Mouse connected?"
            case .alreadyRunning:
                return "A MultitouchReader is already running."
            }
        }
    }

    /// Called for every contact frame, with the fingers and the frame's
    /// timestamp in seconds. Invoked on the framework's own callback thread,
    /// not the main thread.
    public typealias FrameHandler = ([MTFinger], Double) -> Void

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    private var handle: UnsafeMutableRawPointer?
    private var devices: [MTDeviceRef] = []
    private var unregister: MTUnregisterCallbackFn?
    private var stop: MTDeviceStopFn?

    private let handler: FrameHandler

    public private(set) var isRunning = false

    public init(handler: @escaping FrameHandler) {
        self.handler = handler
    }

    deinit {
        stopReading()
    }

    /// Opens the private framework, finds every multitouch device, and starts
    /// delivering frames to the handler.
    public func start() throws {
        guard !isRunning else { throw ReaderError.alreadyRunning }
        guard activeReader == nil else { throw ReaderError.alreadyRunning }

        guard let handle = dlopen(Self.frameworkPath, RTLD_LAZY) else {
            throw ReaderError.frameworkUnavailable(Self.frameworkPath)
        }
        self.handle = handle

        let createList: MTDeviceCreateListFn = try Self.symbol(handle, "MTDeviceCreateList")
        let register: MTRegisterCallbackFn = try Self.symbol(
            handle, "MTRegisterContactFrameCallback"
        )
        let start: MTDeviceStartFn = try Self.symbol(handle, "MTDeviceStart")
        unregister = try Self.symbol(handle, "MTUnregisterContactFrameCallback")
        stop = try Self.symbol(handle, "MTDeviceStop")

        guard let list = createList()?.takeRetainedValue() else {
            throw ReaderError.noDevices
        }

        devices = (0..<CFArrayGetCount(list)).compactMap { index in
            guard let raw = CFArrayGetValueAtIndex(list, index) else { return nil }
            return MTDeviceRef(mutating: raw)
        }

        guard !devices.isEmpty else {
            throw ReaderError.noDevices
        }

        activeReader = self
        for device in devices {
            register(device, magicBindContactFrameCallback)
            start(device, 0)
        }
        isRunning = true
    }

    /// Stops delivery and releases the devices. Safe to call when not running.
    public func stopReading() {
        guard isRunning else { return }
        isRunning = false

        for device in devices {
            stop?(device)
            unregister?(device, magicBindContactFrameCallback)
        }
        devices = []

        if activeReader === self {
            activeReader = nil
        }

        if let handle {
            dlclose(handle)
            self.handle = nil
        }
    }

    fileprivate func deliver(fingers: [MTFinger], timestamp: Double) {
        handler(fingers, timestamp)
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) throws -> T {
        guard let pointer = dlsym(handle, name) else {
            throw ReaderError.symbolUnavailable(name)
        }
        return unsafeBitCast(pointer, to: T.self)
    }
}
