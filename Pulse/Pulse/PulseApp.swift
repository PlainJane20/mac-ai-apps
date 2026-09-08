//
//  PulseApp.swift
//  Pulse
//
//  Created by Navi Sohi on 9/7/26.
//

import SwiftUI
import AppKit
import UserNotifications

@main
struct PulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Pulse", systemImage: "waveform.path.ecg") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Same fix as Lint: without this delegate, macOS silently drops sound
        // for notifications a background/accessory app posts about itself.
        UNUserNotificationCenter.current().delegate = self
        PulseController.shared.requestNotificationPermission()

        PulseController.shared.refreshIfStale()
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
