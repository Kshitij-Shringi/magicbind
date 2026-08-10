import MagicBindCore
import SwiftUI

/// The filled-circle radio button used by the action rows.
struct RadioIndicator: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Theme.onAccent.opacity(0.15) : Theme.surface)
                .frame(width: 18, height: 18)
            Circle()
                .strokeBorder(
                    isSelected ? Theme.onAccent : Theme.hairline,
                    lineWidth: isSelected ? 5 : 1
                )
                .frame(width: 18, height: 18)
        }
    }
}

/// A labelled text field bound to an optional string, treating empty as `nil`
/// so unset parameters stay out of the JSON.
struct InlineTextField: View {
    let title: String
    let prompt: String
    @Binding var value: String?
    var isMultiline: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)

            TextField(
                title,
                text: Binding(
                    get: { value ?? "" },
                    set: { value = $0.isEmpty ? nil : $0 }
                ),
                prompt: Text(prompt),
                axis: isMultiline ? .vertical : .horizontal
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: isMultiline ? .monospaced : .default))
            .foregroundStyle(Theme.primaryText)
            .lineLimit(isMultiline ? 3...8 : 1...1)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline)
            )
        }
    }
}

/// A small inline caution message.
struct InlineWarning: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.warning)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Theme.warning.opacity(0.12))
        )
    }
}
