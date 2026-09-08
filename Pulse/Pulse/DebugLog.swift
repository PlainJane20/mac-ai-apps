//
//  DebugLog.swift
//  Pulse
//
//  print() to stdout gets block-buffered when there's no attached terminal
//  (true for a background-launched GUI app), so it may never reach a
//  redirected log file until the process exits. stderr defaults to
//  unbuffered, so writing there shows up immediately — useful for live
//  debugging without needing Xcode's console attached.
//

import Foundation

func debugLog(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}
