//
//  MicDropApp.swift
//  MicDrop
//
//  Created by Navi Sohi on 9/7/26.
//

import SwiftUI
import AppKit
import UserNotifications

@main
struct MicDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Mic Drop", systemImage: "mic.circle") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        UNUserNotificationCenter.current().delegate = self
        MicDropController.shared.requestNotificationPermission()

        HotKeyManager.shared.onHotKey = {
            MicDropController.shared.toggleRecording()
        }
        HotKeyManager.shared.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregister()
    }

    // Same fix Pulse needed after a real crash: menu-bar-only apps have no
    // real windows, but macOS still tries to restore "window state" on
    // relaunch by default. LSUIElement (set in Info.plist build settings)
    // handles the early-launch AppleEvent path; this covers the newer
    // secure-restoration path too.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
