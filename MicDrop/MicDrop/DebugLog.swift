//
//  DebugLog.swift
//  MicDrop
//
//  Writes to a fixed file path rather than stdout/stderr — MicDrop needs
//  to be launched via `open` (proper LaunchServices launch) for Speech
//  framework's TCC check to work correctly, and `open` detaches the
//  process from whatever shell launched it, so there's no stdout/stderr
//  pipe to redirect at all. A file works regardless of launch method.
//

import Foundation

func debugLog(_ message: String) {
    let path = "/tmp/micdrop-debug.log"
    let line = "\(Date()) — \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: path), let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
