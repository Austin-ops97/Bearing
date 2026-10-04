import SwiftUI

enum BearingTheme {
    static let paper = Color(red: 0.955, green: 0.941, blue: 0.895)
    static let paperRaised = Color(red: 0.984, green: 0.976, blue: 0.945)
    static let charcoal = Color(red: 0.105, green: 0.11, blue: 0.10)
    static let graphite = Color(red: 0.24, green: 0.245, blue: 0.22)
    static let olive = Color(red: 0.31, green: 0.35, blue: 0.21)
    static let oliveSoft = Color(red: 0.80, green: 0.81, blue: 0.69)
    static let amber = Color(red: 0.70, green: 0.48, blue: 0.18)
    static let urgent = Color(red: 0.60, green: 0.20, blue: 0.15)
    static let line = Color.black.opacity(0.13)
}

struct PaperBackground: View {
    var body: some View {
        ZStack {
            BearingTheme.paper
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
                    context.stroke(path, with: .color(BearingTheme.olive.opacity(0.035)), lineWidth: 0.7)
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
                .foregroundStyle(BearingTheme.graphite.opacity(0.75))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(BearingTheme.line).frame(height: 1) }
    }
}

struct OperationalBadge: View {
    let text: String
    let tone: Tone

    enum Tone { case normal, attention, urgent, neutral }

    private var color: Color {
        switch tone {
        case .normal: BearingTheme.olive
        case .attention: BearingTheme.amber
        case .urgent: BearingTheme.urgent
        case .neutral: BearingTheme.graphite
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
    func bearingSurface() -> some View {
        self
            .padding(16)
            .background(BearingTheme.paperRaised.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(BearingTheme.line, lineWidth: 0.7) }
    }
}
