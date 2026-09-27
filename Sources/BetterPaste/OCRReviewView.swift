import SwiftUI

struct OCRReviewView: View {
    @State var text: String
    let onFinish: (String?) -> Void

    var body: some View {
        LiquidGlassContainer {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Review extracted text", systemImage: "text.viewfinder")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Check or edit the text before pasting. Nothing is pasted until you confirm.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                TextEditor(text: $text)
                    .font(.system(size: 13).monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Extracted text")

                HStack {
                    Text("Review any recognition mistakes before pasting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { onFinish(nil) }
                        .keyboardShortcut(.cancelAction)
                    Button("Paste Text") { onFinish(text) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                        .liquidGlassButton()
                }
            }
            .padding(22)
            .liquidGlassSurface(radius: 18)
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
