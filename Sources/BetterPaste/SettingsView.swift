import SwiftUI

struct SettingsView: View {
    @State private var draft: AppConfig
    @State private var saved = false
    let onSave: (AppConfig) -> Void

    init(config: AppConfig, onSave: @escaping (AppConfig) -> Void) {
        _draft = State(initialValue: config)
        self.onSave = onSave
    }

    private var validURLs: Bool {
        [draft.googleURL, draft.chatGPTURL, draft.bingURL, draft.duckDuckGoURL].allSatisfy {
            guard $0.contains("%s"), let url = URL(string: $0.replacingOccurrences(of: "%s", with: "test")),
                  let host = url.host, !host.isEmpty else { return false }
            return ["https", "http"].contains(url.scheme?.lowercased() ?? "")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Clipboard") {
                    Stepper("Clips in picker: \(draft.visibleItemCount)", value: $draft.visibleItemCount, in: 3...15)
                    Stepper("History limit: \(draft.maxHistoryItems)", value: $draft.maxHistoryItems, in: draft.visibleItemCount...500)
                    Toggle("Merge duplicate clips", isOn: $draft.mergeDuplicates)
                    Toggle("Restore clipboard after pasting", isOn: $draft.restoreClipboardAfterPaste)
                    Text("Restores all clipboard formats unless you copy something new. History stays in memory and clears when you quit.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Keyboard shortcut") {
                    Picker("Open picker", selection: $draft.pasteShortcut.modifiers) {
                        Text("Control + V").tag(["control"])
                        Text("Control + Shift + V").tag(["control", "shift"])
                        Text("Command + Shift + V").tag(["command", "shift"])
                        if ![["control"], ["control", "shift"], ["command", "shift"]].contains(draft.pasteShortcut.modifiers) {
                            Text(draft.shortcutDescription).tag(draft.pasteShortcut.modifiers)
                        }
                    }
                    Text("Use ↑ ↓ to browse, Return to paste, and Esc to go back. Press Command + F to edit your search.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Search actions") {
                    TextField("Google", text: $draft.googleURL)
                    TextField("ChatGPT", text: $draft.chatGPTURL)
                    TextField("Bing", text: $draft.bingURL)
                    TextField("DuckDuckGo", text: $draft.duckDuckGoURL)
                    Text(validURLs ? "Use %s for the clip text. Special characters are encoded automatically." : "Each URL needs http:// or https://, a host, and %s for the clip text.")
                        .font(.caption)
                        .foregroundStyle(validURLs ? Color.secondary : Color.red)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Restore Defaults") { draft = .default }
                Spacer()
                if saved { Text("Saved").foregroundStyle(.secondary) }
                Button("Save Changes") {
                    onSave(draft)
                    saved = true
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!validURLs)
            }
            .padding(16)
        }
        .onChange(of: draft) { saved = false }
        .onChange(of: draft.visibleItemCount) {
            draft.maxHistoryItems = max(draft.maxHistoryItems, draft.visibleItemCount)
        }
        .onChange(of: draft.pasteShortcut.modifiers) { draft.pasteShortcut.key = "v" }
        .frame(minWidth: 500, idealWidth: 540, minHeight: 500, idealHeight: 620)
    }
}
