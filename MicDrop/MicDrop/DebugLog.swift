//
//  DebugLog.swift
//  MicDrop
//
//  Same reasoning as Pulse's: print() to stdout gets block-buffered when
//  there's no attached terminal, so it may never reach a redirected log
//  file until the process exits. stderr is unbuffered by default.
//

import Foundation

func debugLog(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}
