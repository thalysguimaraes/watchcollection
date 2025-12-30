import SwiftUI

enum Theme {
    private static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(Color(hex: dark))
            : UIColor(Color(hex: light))
        })
    }

    enum Colors {
        static let accent = adaptive(light: "C6A664", dark: "D4B66A")
        static let accentDark = adaptive(light: "9D844E", dark: "B89A58")
        static let primary = adaptive(light: "0F172A", dark: "E2E8F0")

        static let background = adaptive(light: "FAFAFA", dark: "0D0D0D")
        static let surface = adaptive(light: "FFFFFF", dark: "1A1A1E")
        static let card = adaptive(light: "FFFFFF", dark: "1F1F24")

        static let textPrimary = adaptive(light: "1C1C1E", dark: "F5F5F7")
        static let textSecondary = adaptive(light: "636366", dark: "A1A1A6")
        static let textTertiary = adaptive(light: "8E8E93", dark: "6B6B70")

        static let divider = adaptive(light: "E5E5EA", dark: "2C2C30")

        static let success = adaptive(light: "34C759", dark: "32D74B")
        static let warning = adaptive(light: "FF9F0A", dark: "FFD60A")
        static let error = adaptive(light: "FF3B30", dark: "FF453A")

        static let onAccent = Color.white
        static let onPrimary = adaptive(light: "FFFFFF", dark: "0D0D0D")
        static let popoverBackground = adaptive(light: "0F172A", dark: "1F1F24")
        static let toggleOff = adaptive(light: "D1D1D1", dark: "48484A")
        static let chartSubtle = adaptive(light: "C6A664", dark: "2A2A2E")
    }

    enum Typography {
        static func heading(_ style: Font.TextStyle) -> Font {
            .system(style, design: .default).weight(.semibold)
        }

        static func sans(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
            .system(style, design: .default).weight(weight)
        }
    }

    enum Condition {
        static let unworn = Color(hex: "34C759")
        static let excellent = Color(hex: "007AFF")
        static let veryGood = Color(hex: "5856D6")
        static let good = Color(hex: "FF9500")
        static let fair = Color(hex: "FF3B30")
        static let poor = Color(hex: "8E8E93")
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let card: CGFloat = 12
        static let button: CGFloat = 8
        static let sheet: CGFloat = 20
    }

    enum Shadow {
        static let cardOpacity: Double = 0.08
        static let cardRadius: CGFloat = 12
        static let cardY: CGFloat = 4
        
        static let floatingOpacity: Double = 0.15
        static let floatingRadius: CGFloat = 16
        static let floatingY: CGFloat = 8
    }

    enum Animation {
        static let quick = SwiftUI.Animation.easeOut(duration: 0.15)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let smooth = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.8)
        static let bouncy = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.6)

        static func staggered(index: Int, baseDelay: Double = 0.05) -> SwiftUI.Animation {
            .easeOut(duration: 0.3).delay(Double(index) * baseDelay)
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    init(r: CGFloat, g: CGFloat, b: CGFloat) {
        self.init(.sRGB, red: Double(r), green: Double(g), blue: Double(b))
    }

    var luminance: Double {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
    }

    var contrastingTextColor: Color {
        luminance > 0.7 ? Color(hex: "1C1C1E") : .white
    }

    func darkened(by amount: Double = 0.3) -> Color {
        let uiColor = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(s), brightness: max(0, Double(b) - amount))
    }

    func vibrant(saturation satMult: Double = 1.3, brightness brightMult: Double = 0.9) -> Color {
        let uiColor = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(
            hue: Double(h),
            saturation: min(1.0, Double(s) * satMult),
            brightness: min(1.0, Double(b) * brightMult)
        )
    }

    func saturated(amount: Double = 0.8) -> Color {
        let uiColor = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(
            hue: Double(h),
            saturation: min(1.0, amount),
            brightness: min(1.0, max(0.6, Double(b) * 1.1))
        )
    }

    func adjustedForBackground() -> Color {
        let uiColor = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&h, green: &s, blue: &b, alpha: &a)

        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0
        uiColor.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)

        return Color(
            hue: Double(hue),
            saturation: min(1.0, Double(sat) * 1.3),
            brightness: min(0.85, max(0.55, Double(bri)))
        )
    }

    func brightAccent() -> Color {
        let uiColor = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        return Color(
            hue: Double(h),
            saturation: min(1.0, max(0.5, Double(s) * 1.2)),
            brightness: 1.0
        )
    }
}

extension View {
    func accentTint() -> some View {
        self.tint(Theme.Colors.accent)
    }

    func cardStyle() -> some View {
        self
            .background(Theme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .shadow(
                color: .black.opacity(Theme.Shadow.cardOpacity),
                radius: Theme.Shadow.cardRadius,
                y: Theme.Shadow.cardY
            )
    }

    func pressAnimation() -> some View {
        self.buttonStyle(PressButtonStyle())
    }

    func heading(_ style: Font.TextStyle = .headline) -> some View {
        self.font(Theme.Typography.heading(style))
    }
}

struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(Theme.Animation.quick, value: configuration.isPressed)
    }
}

struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.Colors.onAccent)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)
            .background(
                isEnabled ? Theme.Colors.accent : Theme.Colors.textSecondary
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Theme.Animation.quick, value: configuration.isPressed)
    }
}

struct AccentOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button)
                    .stroke(Theme.Colors.accent, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Theme.Animation.quick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AccentButtonStyle {
    static var accent: AccentButtonStyle { AccentButtonStyle() }
}

extension ButtonStyle where Self == AccentOutlineButtonStyle {
    static var accentOutline: AccentOutlineButtonStyle { AccentOutlineButtonStyle() }
}

struct AccentToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            RoundedRectangle(cornerRadius: 16)
                .fill(configuration.isOn ? Theme.Colors.accent : Theme.Colors.toggleOff)
                .frame(width: 50, height: 30)
                .overlay(
                    Circle()
                        .fill(Theme.Colors.onAccent)
                        .padding(2)
                        .offset(x: configuration.isOn ? 10 : -10)
                )
                .onTapGesture {
                    withAnimation(Theme.Animation.smooth) {
                        configuration.isOn.toggle()
                    }
                }
        }
    }
}

extension ToggleStyle where Self == AccentToggleStyle {
    static var accent: AccentToggleStyle { AccentToggleStyle() }
}
