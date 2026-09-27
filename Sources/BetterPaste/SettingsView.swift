import SwiftUI

struct SettingsView: View {
    @State private var draft: AppConfig
    @State private var saved = false
    @State private var ignoredAppsText: String
    @State private var ignoredPhrasesText: String
    let onSave: (AppConfig) -> Void

    init(config: AppConfig, onSave: @escaping (AppConfig) -> Void) {
        _draft = State(initialValue: config)
        _ignoredAppsText = State(initialValue: config.ignoredBundleIdentifiers.joined(separator: "\n"))
        _ignoredPhrasesText = State(initialValue: config.ignoredTextPatterns.joined(separator: "\n"))
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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                settingsSection("Clipboard", subtitle: "Choose what stays within reach.") {
                    Stepper("Clips in picker: \(draft.visibleItemCount)", value: $draft.visibleItemCount, in: 3...15)
                    Stepper("History limit: \(draft.maxHistoryItems)", value: $draft.maxHistoryItems, in: draft.visibleItemCount...500)
                    Toggle("Merge duplicate clips", isOn: $draft.mergeDuplicates)
                    Toggle("Save history between launches", isOn: $draft.persistHistory)
                    Toggle("Restore clipboard after pasting", isOn: $draft.restoreClipboardAfterPaste)
                    Text("History is stored locally in your user account. Turn this off to keep only pinned clips between launches. Clipboard restoration never replaces a newer copy.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                settingsSection("Keyboard shortcut", subtitle: "Open Better Paste from any app.") {
                    Picker("Open picker", selection: $draft.pasteShortcut.modifiers) {
                        Text("Control + V").tag(["control"])
                        Text("Control + Shift + V").tag(["control", "shift"])
                        Text("Command + Shift + V").tag(["command", "shift"])
                        if ![["control"], ["control", "shift"], ["command", "shift"]].contains(draft.pasteShortcut.modifiers) {
                            Text(draft.shortcutDescription).tag(draft.pasteShortcut.modifiers)
                        }
                    }
                    Text("Use ↑ ↓ to browse, Return to paste, Command + 1–9 for quick paste, Command + P to pin, and Esc to go back.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                settingsSection("Capture exclusions", subtitle: "Keep sensitive apps and text out of history.") {
                    Text("App bundle IDs, one per line").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $ignoredAppsText)
                        .frame(height: 70)
                        .font(.system(size: 12).monospaced())
                    Text("Text containing these phrases, one per line").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $ignoredPhrasesText)
                        .frame(height: 70)
                        .font(.system(size: 12))
                }
                settingsSection("Custom text actions", subtitle: "Run a named replacement from the picker’s Actions menu.") {
                    ForEach($draft.textRules) { $rule in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Action name", text: $rule.name)
                                Button {
                                    draft.textRules.removeAll { $0.id == rule.id }
                                } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain)
                                .help("Remove action")
                            }
                            TextField("Find text or pattern", text: $rule.find)
                            TextField("Replace with", text: $rule.replacement)
                            Toggle("Use regular expression", isOn: $rule.usesRegex)
                            if !rule.isValid {
                                Text("Enter a name and valid search pattern.")
                                    .font(.caption).foregroundStyle(.red)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .padding(10)
                        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                    }
                    Button("Add Text Action") {
                        draft.textRules.append(TextRule(name: "", find: "", replacement: ""))
                    }
                    .disabled(draft.textRules.count >= 12)
                }
                settingsSection("Search actions", subtitle: "Where your selected text goes.") {
                    searchField("Google", text: $draft.googleURL)
                    searchField("ChatGPT", text: $draft.chatGPTURL)
                    searchField("Bing", text: $draft.bingURL)
                    searchField("DuckDuckGo", text: $draft.duckDuckGoURL)
                    Text(validURLs ? "Use %s for the clip text. Special characters are encoded automatically." : "Each URL needs http:// or https://, a host, and %s for the clip text.")
                        .font(.caption)
                        .foregroundStyle(validURLs ? Color.secondary : Color.red)
                }
                }
                .padding(24)
            }
            .scrollIndicators(.automatic)
            Divider().padding(.horizontal, 24)
            HStack {
                Button("Restore Defaults") {
                    draft = .default
                    ignoredAppsText = draft.ignoredBundleIdentifiers.joined(separator: "\n")
                    ignoredPhrasesText = ""
                }
                    .buttonStyle(.borderless)
                Spacer()
                if saved { Text("Saved").foregroundStyle(.secondary) }
                Button("Save Changes") {
                    draft.ignoredBundleIdentifiers = ignoredAppsText.components(separatedBy: .newlines)
                    draft.ignoredTextPatterns = ignoredPhrasesText.components(separatedBy: .newlines)
                    onSave(draft)
                    saved = true
                }
                .keyboardShortcut(.defaultAction)
                .liquidGlassButton()
                .disabled(!validURLs || !draft.textRules.allSatisfy(\.isValid))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .font(.system(size: 13))
        .toggleStyle(.switch)
        .controlSize(.small)
        .liquidGlassSurface(radius: 20)
        .onChange(of: draft) { saved = false }
        .onChange(of: ignoredAppsText) { saved = false }
        .onChange(of: ignoredPhrasesText) { saved = false }
        .onChange(of: draft.visibleItemCount) {
            draft.maxHistoryItems = max(draft.maxHistoryItems, draft.visibleItemCount)
        }
        .onChange(of: draft.pasteShortcut.modifiers) { draft.pasteShortcut.key = "v" }
        .frame(minWidth: 500, idealWidth: 540, minHeight: 500, idealHeight: 620)
    }

    private func settingsSection<Content: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func searchField(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            TextField("https://…?q=%s", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel(title + " search URL")
        }
    }
}
