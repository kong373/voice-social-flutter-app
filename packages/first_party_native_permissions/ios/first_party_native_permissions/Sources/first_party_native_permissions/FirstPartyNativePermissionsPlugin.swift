import AVFoundation
import Flutter
import Photos
import UIKit
import UserNotifications

public final class FirstPartyNativePermissionsPlugin: NSObject, FlutterPlugin {
  private static let channelName = "voice_social_app/system_permissions"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = FirstPartyNativePermissionsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      guard let kind = kind(from: call.arguments) else {
        result(FlutterError(code: "invalid_kind", message: "未知系统权限类型", details: nil))
        return
      }
      status(kind: kind, result: result)
    case "request":
      guard let kind = kind(from: call.arguments) else {
        result(FlutterError(code: "invalid_kind", message: "未知系统权限类型", details: nil))
        return
      }
      request(kind: kind, result: result)
    case "openAppSettings":
      DispatchQueue.main.async {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
          result(false)
          return
        }
        UIApplication.shared.open(url) { opened in result(opened) }
      }
    case "openExternalUrl":
      guard let rawUrl = (call.arguments as? [String: Any])?["url"] as? String,
            let url = URL(string: rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme?.lowercased() == "https",
            let host = url.host, !host.isEmpty,
            url.user == nil else {
        result(false)
        return
      }
      DispatchQueue.main.async {
        guard UIApplication.shared.canOpenURL(url) else {
          result(false)
          return
        }
        UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func kind(from arguments: Any?) -> String? {
    guard let values = arguments as? [String: Any],
          let kind = values["kind"] as? String else { return nil }
    return kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private func status(kind: String, result: @escaping FlutterResult) {
    switch kind {
    case "microphone":
      switch AVAudioSession.sharedInstance().recordPermission {
      case .undetermined: result("notDetermined")
      case .granted: result("granted")
      case .denied: result("permanentlyDenied")
      @unknown default: result("unavailable")
      }
    case "notifications":
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        DispatchQueue.main.async { result(Self.notificationState(settings.authorizationStatus)) }
      }
    case "photos":
      if #available(iOS 14, *) {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .notDetermined: result("notDetermined")
        case .authorized, .limited: result("granted")
        case .denied: result("permanentlyDenied")
        case .restricted: result("restricted")
        @unknown default: result("unavailable")
        }
      } else {
        switch PHPhotoLibrary.authorizationStatus() {
        case .notDetermined: result("notDetermined")
        case .authorized: result("granted")
        case .denied: result("permanentlyDenied")
        case .restricted: result("restricted")
        @unknown default: result("unavailable")
        }
      }
    default:
      result("unavailable")
    }
  }

  private func request(kind: String, result: @escaping FlutterResult) {
    switch kind {
    case "microphone":
      AVAudioSession.sharedInstance().requestRecordPermission { _ in
        self.status(kind: kind, result: result)
      }
    case "notifications":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
        self.status(kind: kind, result: result)
      }
    case "photos":
      if #available(iOS 14, *) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
          self.status(kind: kind, result: result)
        }
      } else {
        PHPhotoLibrary.requestAuthorization { _ in
          self.status(kind: kind, result: result)
        }
      }
    default:
      result("unavailable")
    }
  }

  private static func notificationState(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "notDetermined"
    case .authorized, .provisional, .ephemeral: return "granted"
    case .denied: return "permanentlyDenied"
    @unknown default: return "unavailable"
    }
  }
}
