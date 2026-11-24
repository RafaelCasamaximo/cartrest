import SwiftUI

/// Displays physical dimensions independently of the preview scale.
struct MeasurementDisplay: View {
    struct Reading {
        let name: String
        let value: String
    }

    static let bottomMargin: CGFloat = 24
    static let height: CGFloat = 72
    static let previewBottomInset = height + bottomMargin + 14

    let readings: [Reading]

    private let ink = Color(red: 0.11, green: 0.19, blue: 0.10)
    private let divider = Color(red: 0.32, green: 0.40, blue: 0.25)
    private let housing = RoundedRectangle(cornerRadius: 17)
    private let screen = RoundedRectangle(cornerRadius: 9)

    var body: some View {
        HStack(spacing: 9) {
            screw(rotation: -28)
            HStack(spacing: 0) {
                ForEach(readings.indices, id: \.self) { index in
                    if index > 0 {
                        Rectangle().fill(divider.opacity(0.52))
                            .frame(width: 1, height: 30)
                            .accessibilityHidden(true)
                    }
                    reading(readings[index])
                }
            }
            .padding(.horizontal, 4)
            .frame(maxHeight: .infinity)
            .background(
                screen.fill(LinearGradient(
                    colors: [Color(red: 0.83, green: 0.88, blue: 0.70), Color(red: 0.64, green: 0.73, blue: 0.50)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            )
            .overlay {
                // A lit lower edge and a shadow along the top give the recessed display depth.
                screen.strokeBorder(.black.opacity(0.58), lineWidth: 1)
                screen.inset(by: 1).strokeBorder(
                    LinearGradient(colors: [.black.opacity(0.24), .white.opacity(0.33)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            }
            screw(rotation: 31)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 496)
        .frame(height: Self.height)
        .background(
            housing.fill(LinearGradient(
                stops: [
                    .init(color: Color(red: 0.28, green: 0.32, blue: 0.30), location: 0),
                    .init(color: Color(red: 0.16, green: 0.20, blue: 0.18), location: 0.16),
                    .init(color: Color(red: 0.09, green: 0.12, blue: 0.11), location: 0.93),
                    .init(color: Color(red: 0.17, green: 0.20, blue: 0.18), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            ))
        )
        .overlay {
            housing.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.26), .black.opacity(0.65)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            )
        }
        .shadow(color: .black.opacity(0.42), radius: 14, x: 0, y: 9)
    }

    private func reading(_ reading: Reading) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(reading.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ink.opacity(0.89))
            Text(reading.value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(ink)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func screw(rotation: Double) -> some View {
        Circle()
            .fill(LinearGradient(colors: [Color(white: 0.60), Color(white: 0.20)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { Circle().strokeBorder(.black.opacity(0.68), lineWidth: 1) }
            .overlay {
                Capsule().fill(.black.opacity(0.65))
                    .frame(width: 5, height: 1.1)
                    .rotationEffect(.degrees(rotation))
            }
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}
