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
private typealias MTDeviceGetFamilyIDFn =
    @convention(c) (MTDeviceRef, UnsafeMutablePointer<Int32>) -> Int32
private typealias MTDeviceIsBuiltInFn = @convention(c) (MTDeviceRef) -> Bool
private typealias MTDeviceGetDeviceIDFn =
    @convention(c) (MTDeviceRef, UnsafeMutablePointer<UInt64>) -> Int32
private typealias MTDeviceGetDimensionsFn = @convention(c) (
    MTDeviceRef, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>
) -> Int32

/// The single reader the C callback forwards frames to. `@convention(c)`
/// callbacks can't capture context, so this is how the callback finds its
/// reader. Only one `MultitouchReader` can be started at a time, enforced in
/// `start()`.
private var activeReader: MultitouchReader?

/// The trampoline registered with the private framework.
private func magicBindContactFrameCallback(
    device: MTDeviceRef?,
    fingers: UnsafeMutableRawPointer?,
    count: Int32,
    timestamp: Double,
    frame: Int32
) -> Int32 {
    guard let reader = activeReader, let device else { return 0 }

    var frameFingers: [MTFinger] = []
    if let fingers, count > 0 {
        let typed = fingers.bindMemory(to: MTFinger.self, capacity: Int(count))
        frameFingers = Array(UnsafeBufferPointer(start: typed, count: Int(count)))
    }
    reader.deliver(device: device, fingers: frameFingers, timestamp: timestamp)
    return 0
}

/// Reads raw touch frames from Apple's private
/// `MultitouchSupport.framework`.
///
/// Every attached device is started, and each frame is tagged with the device
/// that produced it. That tagging matters: a Mac with both a Magic Mouse and a
/// trackpad interleaves frames from both, and feeding them into one recognizer
/// would corrupt each other's gesture sessions.
///
/// - Warning: This framework is private and undocumented. It is resolved at
///   runtime with `dlopen`/`dlsym` rather than linked, so a macOS update that
///   removes or renames a symbol degrades to "no gestures" instead of a crash
///   on launch. See `SECURITY.md` for the risk discussion.
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

    /// Called for every contact frame, tagged with the device it came from.
    /// Invoked on the framework's own callback thread, not the main thread.
    public typealias FrameHandler = (MTDeviceInfo, [MTFinger], Double) -> Void

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    private var handle: UnsafeMutableRawPointer?

    /// The device list must outlive `start()`.
    ///
    /// `MTDeviceCreateList` follows the Create rule, so the returned array owns
    /// the device objects. Letting it go out of scope at the end of `start()`
    /// released the devices while `deviceRefs` still held raw pointers to them —
    /// the callback then never fired, because the devices it was registered on
    /// were gone. Symptom: everything reports success, `MTDeviceIsRunning`
    /// returns true, and no frames ever arrive.
    private var deviceList: CFMutableArray?

    private var deviceRefs: [MTDeviceRef] = []
    private var deviceInfo: [MTDeviceRef: MTDeviceInfo] = [:]
    private var unregister: MTUnregisterCallbackFn?
    private var stopDevice: MTDeviceStopFn?

    private let handler: FrameHandler

    public private(set) var isRunning = false

    /// How many contact frames have been delivered since `start()`.
    ///
    /// Surfaced in the UI so "is the reader alive at all" is answerable without
    /// attaching a debugger — the question that cost the most time to answer the
    /// hard way.
    public private(set) var frameCount = 0

    /// Every device found at `start()`, in the order the framework listed them.
    public private(set) var devices: [MTDeviceInfo] = []

    public init(handler: @escaping FrameHandler) {
        self.handler = handler
    }

    deinit {
        stopReading()
    }

    /// Opens the private framework, identifies every multitouch device, and
    /// starts delivering frames.
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
        let startDevice: MTDeviceStartFn = try Self.symbol(handle, "MTDeviceStart")
        unregister = try Self.symbol(handle, "MTUnregisterContactFrameCallback")
        stopDevice = try Self.symbol(handle, "MTDeviceStop")

        guard let list = createList()?.takeRetainedValue() else {
            throw ReaderError.noDevices
        }

        // Hold the array for the reader's lifetime, and retain each device
        // individually as well, so a device survives even if the array is
        // mutated underneath us.
        deviceList = list
        deviceRefs = (0..<CFArrayGetCount(list)).compactMap { index in
            guard let raw = CFArrayGetValueAtIndex(list, index) else { return nil }
            let ref = MTDeviceRef(mutating: raw)
            _ = Unmanaged<AnyObject>.fromOpaque(ref).retain()
            return ref
        }

        guard !deviceRefs.isEmpty else {
            deviceList = nil
            throw ReaderError.noDevices
        }
        frameCount = 0

        deviceInfo = [:]
        devices = []
        for (index, ref) in deviceRefs.enumerated() {
            let info = Self.identify(ref, handle: handle, fallbackID: UInt64(index))
            deviceInfo[ref] = info
            devices.append(info)
        }

        activeReader = self
        for ref in deviceRefs {
            register(ref, magicBindContactFrameCallback)
            startDevice(ref, 0)
        }
        isRunning = true
    }

    /// Stops delivery and releases the devices. Safe to call when not running.
    public func stopReading() {
        guard isRunning else { return }
        isRunning = false

        for ref in deviceRefs {
            stopDevice?(ref)
            unregister?(ref, magicBindContactFrameCallback)
            Unmanaged<AnyObject>.fromOpaque(ref).release()
        }
        deviceRefs = []
        deviceInfo = [:]
        deviceList = nil

        if activeReader === self {
            activeReader = nil
        }

        if let handle {
            dlclose(handle)
            self.handle = nil
        }
    }

    fileprivate func deliver(
        device: MTDeviceRef,
        fingers: [MTFinger],
        timestamp: Double
    ) {
        frameCount += 1
        guard let info = deviceInfo[device] else { return }
        handler(info, fingers, timestamp)
    }

    /// Reads a device's identity. Each accessor is looked up individually and
    /// tolerated as missing, so a macOS release that drops one of these still
    /// leaves gesture recognition working — it just classifies less precisely.
    private static func identify(
        _ ref: MTDeviceRef,
        handle: UnsafeMutableRawPointer,
        fallbackID: UInt64
    ) -> MTDeviceInfo {
        var deviceID = fallbackID
        var familyID: Int32 = -1
        var isBuiltIn = false
        var width: Int32 = 0
        var height: Int32 = 0

        if let pointer = dlsym(handle, "MTDeviceGetDeviceID") {
            let fn = unsafeBitCast(pointer, to: MTDeviceGetDeviceIDFn.self)
            var value: UInt64 = 0
            if fn(ref, &value) == 0, value != 0 {
                deviceID = value
            }
        }
        if let pointer = dlsym(handle, "MTDeviceGetFamilyID") {
            let fn = unsafeBitCast(pointer, to: MTDeviceGetFamilyIDFn.self)
            var value: Int32 = -1
            if fn(ref, &value) == 0 {
                familyID = value
            }
        }
        if let pointer = dlsym(handle, "MTDeviceIsBuiltIn") {
            isBuiltIn = unsafeBitCast(pointer, to: MTDeviceIsBuiltInFn.self)(ref)
        }
        if let pointer = dlsym(handle, "MTDeviceGetSensorSurfaceDimensions") {
            let fn = unsafeBitCast(pointer, to: MTDeviceGetDimensionsFn.self)
            var localWidth: Int32 = 0
            var localHeight: Int32 = 0
            if fn(ref, &localWidth, &localHeight) == 0 {
                width = localWidth
                height = localHeight
            }
        }

        return MTDeviceInfo(
            deviceID: deviceID,
            familyID: familyID,
            isBuiltIn: isBuiltIn,
            surfaceWidth: width,
            surfaceHeight: height
        )
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) throws -> T {
        guard let pointer = dlsym(handle, name) else {
            throw ReaderError.symbolUnavailable(name)
        }
        return unsafeBitCast(pointer, to: T.self)
    }
}
