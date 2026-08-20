import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var store: ClipboardHistoryStore
    @State private var draft: AppConfig
    @Namespace private var controlGlassNamespace

    let onShowPicker: () -> Void
    let onClearHistory: () -> Void
    let onOpenSettings: () -> Void
    let onSaveConfig: (AppConfig) -> Void

    init(
        store: ClipboardHistoryStore,
        config: AppConfig,
        onShowPicker: @escaping () -> Void,
        onClearHistory: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onSaveConfig: @escaping (AppConfig) -> Void
    ) {
        self.store = store
        _draft = State(initialValue: config)
        self.onShowPicker = onShowPicker
        self.onClearHistory = onClearHistory
        self.onOpenSettings = onOpenSettings
        self.onSaveConfig = onSaveConfig
    }

    var body: some View {
        LiquidGlassContainer(spacing: 12) {
            VStack(spacing: 12) {
                header

                VStack(alignment: .leading, spacing: 14) {
                    controls
                    recentList
                    settings
                }
                .padding(16)
                .liquidGlassSurface(radius: 22)
                .liquidGlassID("control-body", in: controlGlassNamespace)
            }
            .padding(12)
        }
        .frame(width: 380, height: 430)
        .background(Color.clear)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .liquidGlassSurface(radius: 12, interactive: true, tint: .accentColor.opacity(0.42))
                .liquidGlassID("app-icon", in: controlGlassNamespace)

            VStack(alignment: .leading, spacing: 2) {
                Text("Better Paste")
                    .font(.system(size: 18, weight: .semibold))
                Text(draft.shortcutDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .liquidGlassSurface(radius: 22)
        .liquidGlassID("control-header", in: controlGlassNamespace)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                onShowPicker()
            } label: {
                Label("Open Picker", systemImage: "rectangle.stack")
                    .frame(maxWidth: .infinity)
            }
            .liquidGlassButton(.accentColor.opacity(0.32))
            .liquidGlassID("open-picker-button", in: controlGlassNamespace)

            Button {
                onClearHistory()
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24)
            }
            .liquidGlassButton()
            .liquidGlassID("clear-history-button", in: controlGlassNamespace)
            .help("Clear clipboard history")
        }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Clips")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(store.visibleItems.count)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if store.visibleItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("Copy text to start building history.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 112)
                .liquidGlassSurface(radius: 14)
                .liquidGlassID("empty-history", in: controlGlassNamespace)
            } else {
                VStack(spacing: 6) {
                    ForEach(store.visibleItems.prefix(4)) { item in
                        CompactClipRow(item: item)
                    }
                }
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Stepper(value: $draft.visibleItemCount, in: 3...15) {
                LabeledContent("Items in picker") {
                    Text("\(draft.visibleItemCount)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: draft.visibleItemCount) {
                onSaveConfig(draft)
            }

            Toggle("Merge duplicate clips", isOn: $draft.mergeDuplicates)
                .onChange(of: draft.mergeDuplicates) {
                    onSaveConfig(draft)
                }

            Button {
                onOpenSettings()
            } label: {
                Label("Advanced Settings", systemImage: "gearshape")
            }
            .liquidGlassButton()
            .liquidGlassID("advanced-settings-button", in: controlGlassNamespace)
        }
    }
}

struct CompactClipRow: View {
    let item: ClipboardItem
    @Namespace private var compactRowGlassNamespace

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.copyCount > 1 ? "rectangle.stack.badge.plus" : "text.alignleft")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .liquidGlassID("compact-row-icon", in: compactRowGlassNamespace)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview.isEmpty ? "Whitespace" : item.preview)
                    .lineLimit(1)
                    .font(.system(size: 13, weight: .medium))
                HStack(spacing: 6) {
                    Text(item.sourceAppName)
                    Text(item.lastCopiedAt, style: .relative)
                    if item.copyCount > 1 {
                        Text("\(item.copyCount)x")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .liquidGlassSurface(radius: 12, interactive: true)
        .liquidGlassID("compact-row", in: compactRowGlassNamespace)
        .liquidGlassMorphTransition()
    }
}
