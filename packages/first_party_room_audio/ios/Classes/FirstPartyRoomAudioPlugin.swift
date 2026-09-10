import AVFoundation
import CoreFoundation
import Flutter
import UIKit

public final class FirstPartyRoomAudioPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private static weak var owner: FirstPartyRoomAudioPlugin?
    private var sessionId: String?
    private var microphone = false
    private var interrupted = false
    private var continuation: InterruptionContinuation?
    private var sink: FlutterEventSink?
    private var observers: [NSObjectProtocol] = []
    private var expiry: Timer?
    private var deadline: TimeInterval = 0
    private var channel: FlutterEventChannel?
    private static let uuid = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = FirstPartyRoomAudioPlugin()
        let methods = FlutterMethodChannel(name: "voice_social_app/room_audio", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: methods)
        registrar.publish(instance) // Required by Flutter for engine-detach notification.
        registrar.addApplicationDelegate(instance)
        instance.channel = FlutterEventChannel(name: "voice_social_app/room_audio/events", binaryMessenger: registrar.messenger())
        instance.channel?.setStreamHandler(instance)
        instance.observe()
    }

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self = self else { return }
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            if type == AVAudioSession.InterruptionType.ended.rawValue {
                self.interrupted = false
                guard var ticket = self.continuation else { return }
                // Duplicate ends must not revoke an in-flight checked resume.
                guard !ticket.ended else { return }
                let raw = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: raw).contains(.shouldResume)
                guard ticket.end(shouldResume: shouldResume, now: ProcessInfo.processInfo.systemUptime),
                      self.eligible(ticket.microphone) else { self.clear(); return }
                self.continuation = ticket
                self.sink?(["sessionId": ticket.sessionId, "active": false, "interruption": "ended"])
            } else if type == AVAudioSession.InterruptionType.began.rawValue {
                guard !self.interrupted else { return }
                self.interrupted = true
                guard let id = self.sessionId else { self.clear(); return }
                self.continuation = InterruptionContinuation(sessionId: id, microphone: self.microphone, deadline: self.deadline)
                self.sessionId = nil; self.microphone = false
                // Keep only the original timer and owner reservation, not audio
                // eligibility. An explicit stop/expiry discards this ticket.
                self.sink?(["sessionId": id, "active": false, "interruption": "began"])
            } else {
                self.interrupted = true
                self.clear()
            }
        })
        for name in [AVAudioSession.mediaServicesWereLostNotification, AVAudioSession.mediaServicesWereResetNotification,
                     UIApplication.willTerminateNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.clear() })
        }
        for name in [AVAudioSession.routeChangeNotification, UIApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.validateLease() })
        }
    }

    // Configuration eligibility only. AVAudioSession exposes no reliable isActive getter.
    // Agora retains all category, activation, route and teardown ownership.
    private func eligible(_ mic: Bool) -> Bool {
        guard !interrupted,
              let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String],
              modes.contains("audio") else { return false }
        let audio = AVAudioSession.sharedInstance()
        if mic {
            return audio.category == .playAndRecord && audio.recordPermission == .granted
        }
        return audio.category == .playAndRecord || audio.category == .playback
    }
    private func validateLease() {
        if sessionId != nil && (ProcessInfo.processInfo.systemUptime >= deadline || !eligible(microphone)) { clear() }
        if let ticket = continuation,
           ProcessInfo.processInfo.systemUptime >= ticket.deadline { clear() }
    }
    private func renew() {
        expiry?.invalidate()
        deadline = ProcessInfo.processInfo.systemUptime + 45
        let timer = Timer(timeInterval: 45, repeats: false) { [weak self] _ in self?.clear() }
        expiry = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func clear() {
        expiry?.invalidate(); expiry = nil
        let old = sessionId ?? continuation?.sessionId
        continuation = nil
        sessionId = nil; microphone = false; deadline = 0
        if Self.owner === self { Self.owner = nil }
        if let old = old { sink?(["sessionId": old, "active": false]) }
    }
    private func arguments(_ call: FlutterMethodCall) -> (String, Bool)? {
        guard let map = call.arguments as? [String: Any],
              Set(map.keys) == (call.method == "start" ? Set(["sessionId", "microphone"]) : Set(["sessionId"])),
              let id = map["sessionId"] as? String,
              id.utf8.count == 36,
              id.range(of: Self.uuid, options: .regularExpression) != nil else { return nil }
        var mic = false
        if call.method == "start" {
            guard let value = map["microphone"] as? NSNumber,
                  CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
            mic = value.boolValue
        }
        return (id, mic)
    }
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard ["start", "stop", "isActive", "renew"].contains(call.method) else { result(FlutterMethodNotImplemented); return }
        guard let (id, mic) = arguments(call) else {
            result(FlutterError(code: "invalid_arguments", message: "Invalid room audio arguments", details: nil)); return
        }
        validateLease()
        switch call.method {
        case "start":
            guard (Self.owner == nil || Self.owner === self),
                  (sessionId == nil || sessionId == id),
                  (continuation == nil || continuation?.sessionId == id) else { result(false); return }
            let foreground = UIApplication.shared.applicationState == .active
            let continuing = continuation?.permits(sessionId: id, microphone: mic, now: ProcessInfo.processInfo.systemUptime) ?? false
            guard (continuation == nil || continuing),
                  (sessionId != nil || foreground || continuing),
                  (!mic || microphone || foreground || continuing), eligible(mic) else { result(false); return }
            continuation = nil
            sessionId = id; microphone = mic; Self.owner = self
            renew()
            sink?(["sessionId": id, "active": true])
            result(true)
        case "stop":
            if sessionId == id || continuation?.sessionId == id { clear() }
            result(nil)
        case "renew":
            let active = sessionId == id
            if active { renew() }
            result(active)
        default:
            result(sessionId == id)
        }
    }
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        guard arguments == nil else { return FlutterError(code: "invalid_arguments", message: "No event arguments allowed", details: nil) }
        sink = events
        validateLease()
        if let id = sessionId { events(["sessionId": id, "active": true]) }
        return nil
    }
    public func onCancel(withArguments arguments: Any?) -> FlutterError? { clear(); sink = nil; return nil }
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        clear()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        channel?.setStreamHandler(nil); channel = nil; sink = nil
    }
    public func applicationWillTerminate(_ application: UIApplication) { clear() }
    deinit {
        expiry?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
