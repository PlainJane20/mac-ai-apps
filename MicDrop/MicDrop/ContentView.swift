//
//  ContentView.swift
//  MicDrop
//
//  The popover shown when you click the menu bar icon.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject private var controller = MicDropController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "mic.circle")
                Text("Mic Drop").font(.headline)
            }

            Text("⌘⌥D toggles dictation anywhere")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !PasteInserter.hasAccessibilityPermission {
                Divider()
                Text("Accessibility access is required to insert text at your cursor.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Grant Accessibility Access") {
                    PasteInserter.requestAccessibilityPermission()
                }
            }

            Divider()

            if controller.isProcessing {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Cleaning up…")
                }
            } else {
                Button(controller.isRecording ? "Stop Dictation" : "Start Dictation") {
                    controller.toggleRecording()
                }
                if controller.isRecording {
                    Label("Recording…", systemImage: "waveform")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            Button("Quit Mic Drop") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}

#Preview {
    ContentView()
}
