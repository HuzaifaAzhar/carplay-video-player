import SwiftUI

/// A keyboard drawn on the car screen for YouTube searches. CarPlay has no keyboard of its own for apps.
/// It fills the screen so the keys are as big as the car allows.
struct CarKeyboardView: View {
    let metrics: CarMetrics
    private let rows = ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"]

    var body: some View {
        let ui = CarUIState.shared
        GeometryReader { geo in
            let gap = max(4, metrics.gap * 0.5)
            let rowCount: CGFloat = 6
            let keyHeight = max(24, (geo.size.height - gap * (rowCount + 1)) / rowCount)
            let keyWidth = max(20, (geo.size.width - gap * 11) / 10)
            let font = Font.system(size: clamp(keyHeight * 0.45, 12, 26), weight: .semibold)

            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    Image(systemName: "magnifyingglass")
                    Text(ui.keyboardText.isEmpty ? "Search YouTube" : ui.keyboardText)
                        .foregroundStyle(ui.keyboardText.isEmpty ? Color.white.opacity(0.5) : Color.white)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: 0)
                    if !ui.keyboardText.isEmpty {
                        key("xmark.circle.fill", width: keyHeight, height: keyHeight, font: font, background: .clear) {
                            ui.keyboardText = ""
                        }
                    }
                }
                .font(font)
                .padding(.horizontal, gap * 2)
                .frame(height: keyHeight)
                .background(RoundedRectangle(cornerRadius: metrics.corner).fill(.white.opacity(0.12)))

                ForEach(rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(Array(row), id: \.self) { character in
                            key(String(character), width: keyWidth, height: keyHeight, font: font) {
                                ui.keyboardText.append(character)
                            }
                        }
                        if row == "zxcvbnm" {
                            key("delete.left.fill", width: keyWidth * 2 + gap, height: keyHeight, font: font) {
                                if !ui.keyboardText.isEmpty { ui.keyboardText.removeLast() }
                            }
                        }
                    }
                }

                HStack(spacing: gap) {
                    key("Cancel", width: keyWidth * 2 + gap, height: keyHeight, font: font) {
                        ui.keyboardVisible = false
                    }
                    key("space", width: keyWidth * 5 + gap * 4, height: keyHeight, font: font) {
                        ui.keyboardText.append(" ")
                    }
                    key("Search", width: keyWidth * 3 + gap * 2, height: keyHeight, font: font, background: Color(red: 0.86, green: 0.08, blue: 0.1)) {
                        ui.searchFromKeyboard()
                    }
                }
            }
            .padding(gap)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black.opacity(0.94).ignoresSafeArea())
    }

    /// A key showing text, or an SF Symbol when the label is a symbol name.
    private func key(_ label: String, width: CGFloat, height: CGFloat, font: Font,
                     background: Color = .white.opacity(0.18), action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if label.contains(".") {
                    Image(systemName: label)
                } else {
                    Text(label)
                }
            }
            .font(font)
            .foregroundStyle(.white)
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: max(4, metrics.corner * 0.6)).fill(background))
            .contentShape(Rectangle())
        }
        .buttonStyle(CarPressStyle())
    }
}
