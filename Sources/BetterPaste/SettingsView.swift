import SwiftUI

struct SettingsView: View {
    @State private var draft: AppConfig
    let onSave: (AppConfig) -> Void
    @Namespace private var settingsGlassNamespace

    init(config: AppConfig, onSave: @escaping (AppConfig) -> Void) {
        _draft = State(initialValue: config)
        self.onSave = onSave
    }

    var body: some View {
        LiquidGlassContainer(spacing: 14) {
            VStack(spacing: 14) {
                settingsSection("Picker") {
                    Stepper(value: $draft.visibleItemCount, in: 3...15) {
                        LabeledContent("Items shown") {
                            Text("\(draft.visibleItemCount)")
                                .monospacedDigit()
                        }
                    }

                    Stepper(value: $draft.maxHistoryItems, in: draft.visibleItemCount...500, step: 10) {
                        LabeledContent("History limit") {
                            Text("\(draft.maxHistoryItems)")
                                .monospacedDigit()
                        }
                    }

                    Toggle("Merge duplicate clips", isOn: $draft.mergeDuplicates)
                    Toggle("Restore previous clipboard after paste", isOn: $draft.restoreClipboardAfterPaste)
                }

                settingsSection("Actions") {
                    glassTextField("Google URL", text: $draft.googleURL)
                    glassTextField("ChatGPT URL", text: $draft.chatGPTURL)
                    glassTextField("Bing URL", text: $draft.bingURL)
                    glassTextField("DuckDuckGo URL", text: $draft.duckDuckGoURL)
                    Text("Use %s where the copied text should be inserted.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                settingsSection("Shortcut") {
                    Text("Default: Control + V")
                        .foregroundStyle(.secondary)
                    Text("Advanced users can edit \(ConfigManager.shared.configURL.path)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Reset") {
                        draft = .default
                        onSave(draft)
                    }
                    .liquidGlassButton()
                    .liquidGlassID("settings-reset", in: settingsGlassNamespace)
                    Spacer()
                    Button("Save") {
                        onSave(draft)
                    }
                    .keyboardShortcut(.defaultAction)
                    .liquidGlassButton(.accentColor.opacity(0.32))
                    .liquidGlassID("settings-save", in: settingsGlassNamespace)
                }
                .padding(.horizontal, 4)
                .liquidGlassID("settings-actions", in: settingsGlassNamespace)
            }
            .padding(18)
        }
        .background(Color.clear)
        .frame(width: 500, height: 540)
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .liquidGlassSurface(radius: 18)
        .liquidGlassID("settings-section-\(title)", in: settingsGlassNamespace)
    }

    private func glassTextField(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 92, alignment: .leading)
                .foregroundStyle(.secondary)
            TextField("Use %s for query", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .liquidGlassSurface(radius: 12, interactive: true)
        .liquidGlassID("settings-field-\(title)", in: settingsGlassNamespace)
        .liquidGlassMorphTransition()
    }
}
