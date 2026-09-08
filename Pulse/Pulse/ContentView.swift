//
//  ContentView.swift
//  Pulse
//
//  The popover shown when you click the menu bar icon — either the
//  first-run Jira setup form, or the actual brief.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject private var controller = PulseController.shared

    var body: some View {
        Group {
            if controller.isConfigured {
                BriefView()
            } else {
                SetupView()
            }
        }
        .onAppear {
            controller.refreshIfStale()
        }
    }
}

struct SetupView: View {
    @ObservedObject private var controller = PulseController.shared
    @State private var baseURL = ""
    @State private var email = ""
    @State private var apiToken = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                Text("Pulse").font(.headline)
            }

            Text("Connect your Jira account. Stored in the macOS Keychain — never in a file.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            TextField("Jira URL — e.g. https://yourcompany.atlassian.net", text: $baseURL)
                .textFieldStyle(.roundedBorder)
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
            SecureField("API Token", text: $apiToken)
                .textFieldStyle(.roundedBorder)

            Text("Generate a token at id.atlassian.com → Manage account → Security → API tokens")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("Save & Connect") {
                controller.saveCredentials(baseURL: baseURL, email: email, apiToken: apiToken)
            }
            .disabled(baseURL.isEmpty || email.isEmpty || apiToken.isEmpty)

            Divider()

            Button("Quit Pulse") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}

struct BriefView: View {
    @ObservedObject private var controller = PulseController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                Text("Pulse").font(.headline)
                Spacer()
                if controller.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await controller.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                }
            }

            if let lastRefreshed = controller.lastRefreshed {
                Text("Updated \(lastRefreshed.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if let error = controller.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if let brief = controller.brief {
                ScrollView {
                    Text(brief)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: 220)
            } else {
                Text("No brief yet — click refresh.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !controller.issues.isEmpty {
                Divider()
                Text("\(controller.issues.count) ticket(s) in active sprints")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Reset Jira Credentials") {
                controller.resetCredentials()
            }
            Button("Quit Pulse") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}

#Preview {
    ContentView()
}
