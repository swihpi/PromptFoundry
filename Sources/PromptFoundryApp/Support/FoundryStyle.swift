import PromptFoundryCore
import SwiftUI

enum FoundryStyle {
    static let accent = Color(red: 0.25, green: 0.70, blue: 0.98)
    static let warmAccent = Color(red: 0.84, green: 0.49, blue: 0.20)
    static let radius: CGFloat = 14
}

struct FoundrySurface: ViewModifier {
    var emphasized = false

    func body(content: Content) -> some View {
        content
            .background(emphasized ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.thinMaterial),
                        in: RoundedRectangle(cornerRadius: FoundryStyle.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FoundryStyle.radius, style: .continuous)
                    .strokeBorder(.white.opacity(emphasized ? 0.17 : 0.10))
            }
            .shadow(color: .black.opacity(emphasized ? 0.09 : 0.045), radius: emphasized ? 16 : 8, y: 5)
    }
}

extension View {
    func foundrySurface(emphasized: Bool = false) -> some View {
        modifier(FoundrySurface(emphasized: emphasized))
    }
}

struct DepthBadge: View {
    let depth: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "slider.horizontal.3")
            Text("Depth \(depth)")
            Text(PromptDepth.title(for: depth))
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(FoundryStyle.accent.opacity(0.12), in: Capsule())
        .foregroundStyle(FoundryStyle.accent)
    }
}
