//
//  ContentView.swift
//  Lint
//
//  The popover shown when you click the menu bar icon.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var controller = LintController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "wand.and.stars")
                Text("Lint").font(.headline)
            }

            Text("⌘⇧V cleans up your clipboard")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button {
                Task { await controller.cleanClipboard() }
            } label: {
                if controller.isCleaning {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Cleaning…")
                    }
                } else {
                    Text("Clean Clipboard Now")
                }
            }
            .disabled(controller.isCleaning)

            Divider()

            Button("Quit Lint") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 240)
    }
}

#Preview {
    ContentView()
}
