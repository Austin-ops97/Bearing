import SwiftUI

struct Microsoft365View: View {
    @StateObject private var microsoft = MicrosoftGraphService.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Connection", value: microsoft.isConnected ? "Connected" : "Not connected")
                if let accountEmail = microsoft.accountEmail {
                    LabeledContent("Work account", value: accountEmail)
                }
                if microsoft.isConfigured {
                    if microsoft.isConnected {
                        Button {
                            Task { await microsoft.refresh() }
                        } label: {
                            Label(microsoft.isRefreshing ? "Refreshing…" : "Refresh Outlook", systemImage: "arrow.clockwise")
                        }
                        .disabled(microsoft.isRefreshing)
                        Button("Disconnect Microsoft 365", role: .destructive) {
                            Task { await microsoft.disconnect() }
                        }
                    } else {
                        Button {
                            Task { await microsoft.connect() }
                        } label: {
                            Label("Connect Work Account", systemImage: "envelope.badge")
                        }
                    }
                } else {
                    Label("Microsoft sign-in needs an Entra app client ID before it can be used.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Microsoft 365")
            } footer: {
                Text("Cailyn requests delegated User.Read, Calendars.Read, and Mail.Read only. Calendar and mail access are read-only; Cailyn cannot send, edit, or delete your work email or meetings. Your organization may require an administrator to approve this app.")
            }

            Section {
                TextField("One sender or email address per line", text: $microsoft.senderPriorityRules, axis: .vertical)
                    .lineLimit(2...6)
                TextField("One priority keyword per line", text: $microsoft.keywordPriorityRules, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("On-Device Email Priority Rules")
            } footer: {
                Text("Cailyn applies these rules locally to downloaded sender, subject, and preview text. Microsoft-marked Important, flagged, unread, and common urgency terms also contribute. These rules do not change Outlook.")
            }

            if microsoft.isConnected {
                Section("Likely Work Priorities · \(microsoft.prioritizedMessages.count)") {
                    if microsoft.prioritizedMessages.isEmpty {
                        ContentUnavailableView("No Prioritized Emails", systemImage: "envelope.open", description: Text("No downloaded messages match current priority rules."))
                    } else {
                        ForEach(microsoft.prioritizedMessages) { message in
                            emailRow(message)
                        }
                    }
                }
                Section("Upcoming Outlook / Teams Meetings · \(microsoft.events.count)") {
                    if microsoft.events.isEmpty {
                        ContentUnavailableView("No Meetings Found", systemImage: "calendar", description: Text("No events were returned for the selected date range."))
                    } else {
                        ForEach(microsoft.events) { event in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(event.subject ?? "Untitled meeting").font(.headline)
                                Text("\(event.start.dateTime) · \(event.start.timeZone)")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let location = event.location?.displayName {
                                    Label(location, systemImage: "mappin.and.ellipse").font(.caption)
                                }
                                if let joinURL = event.onlineMeeting?.joinUrl, let url = URL(string: joinURL) {
                                    Link("Join Teams meeting", destination: url)
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            if let errorMessage = microsoft.errorMessage {
                Section("Connection Status") {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("OUTLOOK & TEAMS")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if microsoft.isConnected, microsoft.events.isEmpty, microsoft.messages.isEmpty {
                await microsoft.refresh()
            }
        }
    }

    @ViewBuilder
    private func emailRow(_ message: MicrosoftGraphMessage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(message.subject ?? "Untitled").font(.headline).lineLimit(2)
                Spacer()
                Text(message.priorityLabel.uppercased())
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(CailynTheme.champagne)
            }
            Text("\(message.from?.emailAddress.name ?? "Unknown sender") · \(message.receivedDateTime?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown date")")
                .font(.caption).foregroundStyle(.secondary)
            if let preview = message.bodyPreview, !preview.isEmpty {
                Text(preview).font(.subheadline).lineLimit(3)
            }
            if let link = message.webLink, let url = URL(string: link) {
                Link("Open in Outlook", destination: url).font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 5)
    }
}
