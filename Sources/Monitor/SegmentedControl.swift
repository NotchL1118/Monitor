import SwiftUI

/// The app's one segmented control: a recessed track with a raised white selection.
struct SegmentedControl<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    var compact = false
    let title: (Value) -> String
    var accessibilityTitle: ((Value) -> String)?
    var identifier: ((Value) -> String)?
    @State private var hovered: Value?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let active = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.system(size: compact ? 12 : 13, weight: active ? .semibold : .medium))
                        .foregroundStyle(active || hovered == option ? Palette.ink : Palette.ink.opacity(0.72))
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, compact ? 10 : 13).frame(height: compact ? 24 : 28)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 6).fill(.white)
                                    .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.black.opacity(0.05), lineWidth: 0.5))
                            }
                        }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .onHover { inside in
                        if inside { hovered = option } else if hovered == option { hovered = nil }
                    }
                    .accessibilityLabel(accessibilityTitle?(option) ?? title(option))
                    .accessibilityAddTraits(active ? .isSelected : [])
                    .accessibilityIdentifier(identifier?(option) ?? "")
            }
        }
        .padding(2)
        .background(Palette.sunk, in: RoundedRectangle(cornerRadius: 8))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .animation(.easeOut(duration: 0.12), value: selection)
    }
}
