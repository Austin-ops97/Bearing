import SwiftUI
import UIKit

enum CailynTheme {
    static let paper = adaptive(light: UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1), dark: UIColor(red: 0.035, green: 0.035, blue: 0.04, alpha: 1))
    static let paperRaised = adaptive(light: UIColor(red: 0.99, green: 0.985, blue: 0.97, alpha: 1), dark: UIColor(red: 0.075, green: 0.073, blue: 0.071, alpha: 1))
    static let charcoal = adaptive(light: UIColor(red: 0.09, green: 0.085, blue: 0.08, alpha: 1), dark: UIColor(red: 0.02, green: 0.02, blue: 0.024, alpha: 1))
    static let graphite = adaptive(light: UIColor(red: 0.25, green: 0.235, blue: 0.215, alpha: 1), dark: UIColor(red: 0.82, green: 0.79, blue: 0.73, alpha: 1))
    static let champagne = adaptive(light: UIColor(red: 0.48, green: 0.33, blue: 0.19, alpha: 1), dark: UIColor(red: 0.91, green: 0.74, blue: 0.52, alpha: 1))
    static let champagneMuted = adaptive(light: UIColor(red: 0.84, green: 0.77, blue: 0.65, alpha: 1), dark: UIColor(red: 0.31, green: 0.25, blue: 0.18, alpha: 1))
    static let champagneGlow = adaptive(light: UIColor(red: 0.62, green: 0.40, blue: 0.19, alpha: 1), dark: UIColor(red: 0.96, green: 0.83, blue: 0.64, alpha: 1))
    static let urgent = adaptive(light: UIColor(red: 0.60, green: 0.20, blue: 0.15, alpha: 1), dark: UIColor(red: 0.96, green: 0.43, blue: 0.36, alpha: 1))
    static let line = Color(uiColor: .separator).opacity(0.65)

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

struct PaperBackground: View {
    var body: some View {
        ZStack {
            CailynTheme.paper
            RadialGradient(
                colors: [CailynTheme.champagneGlow.opacity(0.09), .clear],
                center: .topTrailing,
                startRadius: 4,
                endRadius: 520
            )
            Canvas { context, size in
                for index in 0..<14 {
                    let y = size.height * CGFloat(index + 1) / 15
                    var path = Path()
                    path.move(to: CGPoint(x: -20, y: y))
                    for step in 0...8 {
                        let x = size.width * CGFloat(step) / 8
                        let offset = sin(CGFloat(step + index) * 0.9) * 5
                        path.addLine(to: CGPoint(x: x, y: y + offset))
                    }
                    context.stroke(path, with: .color(CailynTheme.champagne.opacity(0.028)), lineWidth: 0.7)
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

struct SectionHeading: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(CailynTheme.line).frame(height: 1) }
    }
}

struct OperationalBadge: View {
    let text: String
    let tone: Tone

    enum Tone { case normal, attention, urgent, neutral }

    private var color: Color {
        switch tone {
        case .normal: CailynTheme.champagne
        case .attention: CailynTheme.champagneGlow
        case .urgent: CailynTheme.urgent
        case .neutral: CailynTheme.graphite
        }
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.11), in: Capsule())
    }
}

extension View {
    func cailynSurface() -> some View {
        self
            .padding(16)
            .background(CailynTheme.paperRaised.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(CailynTheme.line, lineWidth: 0.7) }
    }
}
