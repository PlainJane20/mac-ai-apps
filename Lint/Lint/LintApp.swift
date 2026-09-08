//
//  LintApp.swift
//  Lint
//
//  Created by Navi Sohi on 9/7/26.
//

import SwiftUI
import AppKit
import UserNotifications

@main
struct LintApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // MenuBarExtra is SwiftUI's built-in "live in the menu bar" scene —
        // no manual NSStatusItem setup needed.
        MenuBarExtra("Lint", systemImage: "wand.and.stars") {
            ContentView()
        }
        .menuBarExtraStyle(.window) // custom-shaped popover instead of a plain menu list
    }
}

/// SwiftUI's App protocol doesn't have a "did finish launching" hook, so we
/// bring in a small AppKit delegate just for startup wiring: hiding the Dock
/// icon and registering the global hotkey.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app — no Dock icon, no app switcher entry.
        NSApp.setActivationPolicy(.accessory)

        // Without a delegate, macOS silently drops the sound (and sometimes the
        // banner) for notifications posted by the app that's currently frontmost —
        // which is exactly our case, since you click Lint's own popover to trigger
        // this. Explicitly confirming .banner + .sound here overrides that.
        UNUserNotificationCenter.current().delegate = self
        LintController.shared.requestNotificationPermission()

        HotKeyManager.shared.onHotKey = {
            Task { await LintController.shared.cleanClipboard() }
        }
        HotKeyManager.shared.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregister()
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
