import SwiftUI

extension View {
    @ViewBuilder
    func liquidGlassSurface(radius: CGFloat = 18, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            if let tint {
                glassEffect(.regular.tint(tint).interactive(interactive), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            } else {
                glassEffect(.regular.interactive(interactive), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
        } else {
            background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }

    @ViewBuilder
    func clearGlassSurface(radius: CGFloat = 18, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.clear.interactive(interactive), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }

    @ViewBuilder
    func liquidGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func liquidGlassButton(_ tint: Color?) -> some View {
        if #available(macOS 26.1, *) {
            buttonStyle(.glass(tint.map { .regular.tint($0).interactive() } ?? .regular.interactive()))
        } else if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func liquidGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func liquidGlassMorphTransition() -> some View {
        if #available(macOS 26.0, *) {
            glassEffectTransition(.matchedGeometry)
        } else {
            self
        }
    }
}

@ViewBuilder
func LiquidGlassContainer<Content: View>(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) -> some View {
    if #available(macOS 26.0, *) {
        GlassEffectContainer(spacing: spacing, content: content)
    } else {
        content()
    }
}
