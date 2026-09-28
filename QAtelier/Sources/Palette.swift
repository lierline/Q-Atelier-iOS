import UIKit

/// 안드로이드 앱 res/values/colors.xml 과 같은 색
enum Palette {
    static let appBgLight = PageColor(rgb: 0xFAF9F6)
    static let appBgDark = PageColor(rgb: 0x0C0C0C)
    static let accent = UIColor(rgb: 0xB8935A)
    static let accentBright = UIColor(rgb: 0xD9B779)
    static let mutedOnDark = UIColor(rgb: 0xA39D90)
    static let mutedOnLight = UIColor(rgb: 0x6B665C)
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)
    }
}

/// 화면 바탕색 한 가지. 사이트가 bridge.js 로 알리는 '#rrggbb' 모양만 받는다
struct PageColor: Equatable {
    let rgb: UInt32

    init(rgb: UInt32) {
        self.rgb = rgb & 0xFFFFFF
    }

    init?(hex: String) {
        let digits = hex.dropFirst()
        guard hex.count == 7, hex.first == "#", digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16) else { return nil }
        rgb = value
    }

    var hex: String { String(format: "#%06x", rgb) }

    var color: UIColor { UIColor(rgb: rgb) }

    /// 사람 눈의 밝기(가중 합)로 어두운 색인지. 어두우면 상태 표시줄 글자를 밝게(안드로이드 isDark 와 같은 식)
    var isDark: Bool {
        let r = (rgb >> 16) & 0xFF, g = (rgb >> 8) & 0xFF, b = rgb & 0xFF
        return (r * 299 + g * 587 + b * 114) / 1000 < 128
    }
}
