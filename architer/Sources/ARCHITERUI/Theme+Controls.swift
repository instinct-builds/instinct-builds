#if os(macOS)
import SwiftUI

/// Themed controls built on Theme tokens (0.3.0 design language).

/// Brass-accented pill button for rolls and primary affordances.
struct RollButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typeface.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                (prominent ? Theme.accent.opacity(configuration.isPressed ? 0.55 : 0.35) : Theme.accentSoft.opacity(configuration.isPressed ? 1.6 : 1.0)),
                in: RoundedRectangle(cornerRadius: Theme.Radius.sm)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .strokeBorder(Theme.accent.opacity(prominent ? 0.8 : 0.45), lineWidth: 1)
            )
            .foregroundStyle(prominent ? Theme.ink : Theme.accent)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

/// Quiet inset text field on the dark surface.
struct InsetFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(Theme.Typeface.body)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .strokeBorder(Theme.edge.opacity(0.7), lineWidth: 1)
            )
            .foregroundStyle(Theme.ink)
    }
}

/// Filled/empty pips for slots, death saves, hit dice.
struct Pips: View {
    let filled: Int
    let total: Int
    var tint: Color = Theme.accent
    var size: CGFloat = 10
    var onTap: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < filled ? tint : Color.clear)
                    .overlay(Circle().strokeBorder(i < filled ? tint : Theme.inkFaint, lineWidth: 1.2))
                    .frame(width: size, height: size)
                    .contentShape(Circle())
                    .onTapGesture { onTap?(i) }
            }
        }
    }
}

/// Small stat plate: label above value on an inset surface.
struct StatPlate: View {
    let label: String
    let value: String
    var tint: Color = Theme.ink

    var body: some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(Theme.Typeface.statLabel)
                .tracking(1)
                .foregroundStyle(Theme.inkMuted)
            Text(value)
                .font(Theme.Typeface.statBig)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(Theme.edge.opacity(0.6), lineWidth: 1)
        )
    }
}

/// Horizontal HP/resource bar.
struct ResourceBar: View {
    let current: Int
    let max: Int
    var temp: Int = 0

    var body: some View {
        GeometryReader { geo in
            let frac = max > 0 ? min(1, CGFloat(current) / CGFloat(max)) : 0
            let tempFrac = max > 0 ? min(1 - frac, CGFloat(temp) / CGFloat(max)) : 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(Theme.surfaceInset)
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(frac > 0.5 ? Theme.success : (frac > 0.25 ? Theme.accent : Theme.danger))
                    .frame(width: geo.size.width * frac)
                if temp > 0 {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(Theme.arcana.opacity(0.7))
                        .frame(width: geo.size.width * tempFrac)
                        .offset(x: geo.size.width * frac)
                }
            }
        }
        .frame(height: 8)
    }
}

/// Section label used inside cards between groups.
struct CardSectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typeface.statLabel)
            .tracking(1.2)
            .foregroundStyle(Theme.inkFaint)
    }
}
#endif
