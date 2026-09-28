import CoreText
import QuartzCore
import UIKit

/// 앱을 켤 때의 장면. 안드로이드 앱 2.5.0 의 LaunchView 를 옮겼다(오너 선택 「가 · 붓이 긋는 Q」 · 2026-09-27).
///
/// 앱 아이콘(동그라미 틀)을 다시 띄우지 않고 웹 로그인 화면과 같은 짝(동그라미 없는 붓 Q + Q-ATELIER)을 그린다.
///
///     0~650ms     붓 Q 의 둥근 획이 위에서부터 시계 방향으로 그려진다
///     330~780ms   꼬리와 붓이 왼쪽에서 오른쪽으로 그어진다
///     780~1200ms  은빛(밝은 바탕이면 검은 칠)에 빛이 한 번 스친다
///     700~1200ms  글자 Q-ATELIER 가 자간을 좁히며 나타난다
///
/// 첫 화면이 먼저 준비돼도 장면을 끝까지 보여 준 뒤 걷는다(오너 결정 「끝까지 보여 줌」). 더 늦으면 글자 아래 실선에
/// 빛이 오가고, 8초가 넘으면 «연결이 느립니다. 기다리는 중…». 걷힐 때는 0.28초 동안 살짝 올라가며 흐려진다.
/// 덮는 동안 밑의 웹 화면은 눌리지 않는다.
///
/// iOS 의 «동작 줄이기»(손쉬운 사용)가 켜져 있으면 장면 없이 다 그려진 모습만 덮었다가 바로 걷는다. 안드로이드의
/// «애니메이션 배율» 에 해당하는 것이 iOS 에는 없어, 장면을 한 장씩 확인할 때는 실행 인자
/// `-QALaunchTimeScale 8` 처럼 배율을 준다(깃허브 맥의 시뮬레이터 촬영이 쓴다).
final class LaunchView: UIView {
    static let introMs = 1200.0
    static let slowHintMs = 8000.0
    private static let bowlEnd = 650.0
    private static let tailStart = 330.0
    private static let tailEnd = 780.0
    private static let glintStart = 780.0
    private static let wordStart = 700.0
    private static let waitFadeMs = 300.0
    private static let waitPeriodMs = 1100.0
    private static let exitMs = 280.0

    /// 붓 Q 그림 안의 자리(0~1). 둥근 획은 가운데(0.5, 0.44)를 돌며 드러나고, 꼬리 · 붓은 사선(왼쪽 70% → 오른쪽 86%)
    /// 아래에서 왼쪽부터 드러난다. 수평선으로 가르면 오른쪽 아래 둥근 획이 선에서 한동안 끊겨 보였다(안드로이드 시안 실측)
    private static let bowlCX: CGFloat = 0.5
    private static let bowlCY: CGFloat = 0.44
    private static let splitLeft: CGFloat = 0.70
    private static let splitRight: CGFloat = 0.86
    private static let wordmark = "Q-ATELIER"
    private static let slowHint = "연결이 느립니다. 기다리는 중…"

    private static let bowlEase = CubicBezier(0.55, 0.05, 0.35, 1)
    private static let tailEase = CubicBezier(0.45, 0, 0.3, 1)
    private static let softEase = CubicBezier(0.2, 0.7, 0.2, 1)
    private static let inOut = CubicBezier(0.42, 0, 0.58, 1)

    private let bg: PageColor
    private let animate: Bool
    private let motionOff: Bool
    private let timeScale: Double
    private let mark: UIImage?
    private let muted: UIColor
    private let accentBright: UIColor
    private let wordFont: UIFont
    private let hintFont = UIFont.systemFont(ofSize: 13)
    /// «Q-ATELIER» 글자 모양이 차지하는 칸(기준선 기준 · 위가 +)
    private let wordGlyphs: CGRect
    private let canvas = LaunchCanvas()

    // 자리 (layoutSubviews)
    private var markRect = CGRect.zero
    private var centerX: CGFloat = 0
    private var wordBaseline: CGFloat = 0
    private var lineY: CGFloat = 0
    private var hintBaseline: CGFloat = 0
    private var bowlArea: CGPath = CGMutablePath()
    private var tailArea: CGPath = CGMutablePath()

    // 시간 (tick). 밀리초
    private var link: CADisplayLink?
    private var start: CFTimeInterval = -1
    private var waitStart: CFTimeInterval = -1
    private var exitStart: CFTimeInterval = -1
    private var exitAsked = false
    private var onGone: (() -> Void)?
    private var elapsed = 0.0
    private var intro = 0.0
    private var exitProgress = 0.0
    private var waitSince = -1.0

    /// - Parameters:
    ///   - bg: 바탕색(마지막 사이트 바탕 · 모르면 폰의 밤낮). 어두우면 은빛 Q, 밝으면 검은 칠 Q
    ///   - animate: 앱을 켤 때는 장면을 돌리고, 웹 엔진이 멈춰 다시 열 때는 다 그려진 모습만 덮는다
    init(bg: PageColor, animate: Bool) {
        self.bg = bg
        let reduce = UIAccessibility.isReduceMotionEnabled
        let runs = animate && !reduce
        motionOff = reduce
        self.animate = runs
        let scale = UserDefaults.standard.double(forKey: "QALaunchTimeScale")
        timeScale = scale > 0 ? scale : 1
        let dark = bg.isDark
        mark = UIImage(named: dark ? "launch-q-on-dark" : "launch-q-on-light")
        muted = dark ? Palette.mutedOnDark : Palette.mutedOnLight
        accentBright = dark ? Palette.accentBright : Palette.accent
        let font = Self.wordmarkFont(size: 11)
        wordFont = font
        let measured = NSAttributedString(string: Self.wordmark, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(measured as CFAttributedString)
        wordGlyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        intro = runs ? 0 : Self.introMs
        super.init(frame: .zero)
        backgroundColor = bg.color
        canvas.owner = self
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.isUserInteractionEnabled = false
        canvas.contentMode = .redraw
        addSubview(canvas)
        isAccessibilityElement = true
        accessibilityLabel = "불러오는 중"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    /// 첫 화면이 보였다. 장면이 끝났으면 바로, 아니면 끝까지 보여 준 뒤 걷고 onGone 을 부른다
    func finish(_ onGone: @escaping () -> Void) {
        self.onGone = onGone
        exitAsked = true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, link == nil {
            let l = CADisplayLink(target: self, selector: #selector(tick))
            l.add(to: .main, forMode: .common)
            link = l
        } else if window == nil {
            link?.invalidate()
            link = nil
        }
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        if start < 0 { start = now }
        elapsed = (now - start) * 1000
        intro = animate ? elapsed / timeScale : Self.introMs
        if exitAsked && exitStart < 0 && intro >= Self.introMs { exitStart = now }
        if exitStart < 0 {
            exitProgress = 0
        } else {
            exitProgress = motionOff ? 1 : Self.clamp((now - exitStart) * 1000 / (Self.exitMs * timeScale))
        }
        if exitProgress >= 1 {
            link?.invalidate()
            link = nil
            let gone = onGone
            onGone = nil
            gone?()
            return
        }
        if exitStart < 0 && intro >= Self.introMs && waitStart < 0 { waitStart = now }
        waitSince = waitStart < 0 ? -1 : (now - waitStart) * 1000 / timeScale
        backgroundColor = bg.color.withAlphaComponent(CGFloat(1 - exitProgress))
        canvas.setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 붓 Q 와 글자를 한 묶음으로 화면 한가운데에
        let w: CGFloat = 120
        let h: CGFloat = mark.map { w * $0.size.height / max($0.size.width, 1) } ?? w
        let gap: CGFloat = 18
        let groupTop = bounds.midY - (h + gap + wordGlyphs.height) / 2
        centerX = bounds.midX
        markRect = CGRect(x: centerX - w / 2, y: groupTop, width: w, height: h)
        wordBaseline = markRect.maxY + gap + wordGlyphs.maxY
        lineY = wordBaseline + 22
        hintBaseline = lineY + 18 + hintFont.pointSize

        let yl = markRect.minY + h * Self.splitLeft
        let yr = markRect.minY + h * Self.splitRight
        let l = markRect.minX - 1
        let r = markRect.maxX + 1
        let bowl = CGMutablePath()
        bowl.move(to: CGPoint(x: l, y: markRect.minY - 1))
        bowl.addLine(to: CGPoint(x: r, y: markRect.minY - 1))
        bowl.addLine(to: CGPoint(x: r, y: yr))
        bowl.addLine(to: CGPoint(x: l, y: yl))
        bowl.closeSubpath()
        bowlArea = bowl
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: l, y: yl))
        tail.addLine(to: CGPoint(x: r, y: yr))
        tail.addLine(to: CGPoint(x: r, y: markRect.maxY + 1))
        tail.addLine(to: CGPoint(x: l, y: markRect.maxY + 1))
        tail.closeSubpath()
        tailArea = tail

        // 그리는 판은 붓 Q 부터 느림 안내 아래까지만(화면 전체를 매 장 다시 그리지 않게). 바탕은 이 판 밖에서 칠한다
        let top = markRect.minY - 16
        canvas.frame = CGRect(x: 0, y: top, width: bounds.width, height: hintBaseline + 12 - top)
        canvas.setNeedsDisplay()
    }

    // MARK: 그리기

    fileprivate func render(in ctx: CGContext) {
        let alpha = CGFloat(1 - exitProgress)
        guard alpha > 0 else { return }
        ctx.saveGState()
        ctx.translateBy(x: 0, y: -8 * CGFloat(exitProgress * exitProgress))
        drawMark(ctx, t: intro, alpha: alpha)
        drawWordmark(ctx, t: intro, alpha: alpha)
        if waitSince >= 0 { drawWait(ctx, since: waitSince, alpha: alpha) }
        if elapsed >= Self.slowHintMs { drawHint(ctx, since: elapsed - Self.slowHintMs, alpha: alpha) }
        ctx.restoreGState()
    }

    private func drawMark(_ ctx: CGContext, t: Double, alpha: CGFloat) {
        guard let mark else { return }
        let layerRect = markRect.insetBy(dx: -2, dy: -2)
        if t >= Self.tailEnd {
            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.beginTransparencyLayer(in: layerRect, auxiliaryInfo: nil)
            mark.draw(in: markRect)
            if t < Self.introMs { drawGlint(ctx, g: (t - Self.glintStart) / (Self.introMs - Self.glintStart)) }
            ctx.endTransparencyLayer()
            ctx.restoreGState()
            return
        }
        let bowl = Self.bowlEase(Self.clamp(t / Self.bowlEnd))
        if bowl > 0 {
            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.beginTransparencyLayer(in: layerRect, auxiliaryInfo: nil)
            ctx.addPath(bowlArea)
            ctx.clip()
            mark.draw(in: markRect)
            if bowl < 1 { eraseUnswept(ctx, f: bowl) }
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
        let tail = Self.tailEase(Self.clamp((t - Self.tailStart) / (Self.tailEnd - Self.tailStart)))
        if tail > 0 {
            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.beginTransparencyLayer(in: layerRect, auxiliaryInfo: nil)
            ctx.addPath(tailArea)
            ctx.clip()
            mark.draw(in: markRect)
            eraseAfterWipe(ctx, f: tail)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
    }

    /// 12시에서 12° 앞서 시작해 시계 방향으로 372° 도는 부채꼴 밖을 지운다. 앞 끝은 4° 쯤 부드럽게
    private func eraseUnswept(_ ctx: CGContext, f: Double) {
        let center = CGPoint(x: markRect.minX + markRect.width * Self.bowlCX, y: markRect.minY + markRect.height * Self.bowlCY)
        let radius = hypot(markRect.width, markRect.height)
        let begin = -102.0 * Double.pi / 180
        let full = begin + 2 * Double.pi
        let edge = begin + min(1, f * 372 / 360) * 2 * Double.pi
        let soft = 0.012 * 2 * Double.pi
        ctx.setBlendMode(.destinationOut)
        // 조각끼리 맞닿는 선이 비치지 않게 가장자리 흐림을 끈다. 앞 끝은 아래 네 조각이 부드럽게 한다
        ctx.setShouldAntialias(false)
        let steps = 4
        for i in 0..<steps {
            let a0 = edge + soft * Double(i) / Double(steps)
            guard a0 < full else { break }
            let a1 = min(edge + soft * Double(i + 1) / Double(steps), full)
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: CGFloat(i + 1) / CGFloat(steps + 1)))
            ctx.addPath(Self.sector(center: center, radius: radius, from: a0, to: a1))
            ctx.fillPath()
        }
        if edge + soft < full {
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.addPath(Self.sector(center: center, radius: radius, from: edge + soft, to: full))
            ctx.fillPath()
        }
        ctx.setShouldAntialias(true)
        ctx.setBlendMode(.normal)
    }

    /// 왼쪽에서 오른쪽으로 지나가는 경계(폭의 10% 만큼 부드럽게). 경계 오른쪽을 지운다
    private func eraseAfterWipe(_ ctx: CGContext, f: Double) {
        let w = markRect.width
        let x = markRect.minX + w * CGFloat(-0.12 + 1.24 * f)
        ctx.setBlendMode(.destinationOut)
        ctx.drawLinearGradient(
            Self.wipeGradient,
            start: CGPoint(x: x, y: 0),
            end: CGPoint(x: x + w * 0.1, y: 0),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.setBlendMode(.normal)
    }

    /// 오른쪽 아래로 22° 기운 좁은 빛 띠가 왼쪽에서 오른쪽으로 한 번 스친다. 그림이 있는 곳에만 비친다(sourceAtop)
    private func drawGlint(_ ctx: CGContext, g: Double) {
        guard g > 0, g < 1 else { return }
        let len = markRect.width * 0.5
        let angle = 22.0 * Double.pi / 180
        let dx = CGFloat(cos(angle)) * len
        let dy = CGFloat(sin(angle)) * len
        let p = Self.inOut(g)
        let envelope = g < 0.25 ? g / 0.25 : (1 - g) / 0.75
        let cx = markRect.minX + markRect.width * CGFloat(-0.3 + 1.6 * p)
        let cy = markRect.midY
        ctx.saveGState()
        ctx.clip(to: markRect)
        ctx.setBlendMode(.sourceAtop)
        ctx.setAlpha(CGFloat(0.9 * envelope))
        ctx.drawLinearGradient(
            Self.glintGradient,
            start: CGPoint(x: cx - dx, y: cy - dy),
            end: CGPoint(x: cx + dx, y: cy + dy),
            options: [])
        ctx.restoreGState()
    }

    private func drawWordmark(_ ctx: CGContext, t: Double, alpha: CGFloat) {
        let f = Self.softEase(Self.clamp((t - Self.wordStart) / (Self.introMs - Self.wordStart)))
        guard f > 0 else { return }
        // 안드로이드 letterSpacing(글자 크기의 0.7 → 0.32 배)과 같은 자간
        let em = CGFloat(0.7 - 0.38 * f)
        drawCentered(
            ctx, Self.wordmark, font: wordFont,
            color: muted.withAlphaComponent(CGFloat(f) * alpha),
            kern: em * wordFont.pointSize, baseline: wordBaseline)
    }

    /// 늦을 때: 글자 아래 64pt 실선 위로 밝은 금빛이 오간다
    private func drawWait(_ ctx: CGContext, since: Double, alpha: CGFloat) {
        let f = CGFloat(Self.clamp(since / Self.waitFadeMs)) * alpha
        guard f > 0 else { return }
        let half: CGFloat = 32
        let track = CGRect(x: centerX - half, y: lineY, width: half * 2, height: 1)
        ctx.setFillColor(Palette.accent.withAlphaComponent(0.25 * f).cgColor)
        ctx.fill(track)
        let seg = half * 2 * 0.4
        let phase = CGFloat(Self.inOut(since.truncatingRemainder(dividingBy: Self.waitPeriodMs) / Self.waitPeriodMs))
        let x = centerX - half - seg + (half * 2 + seg) * phase
        ctx.saveGState()
        ctx.clip(to: track)
        ctx.setFillColor(accentBright.withAlphaComponent(f).cgColor)
        ctx.fill(CGRect(x: x, y: lineY, width: seg, height: 1))
        ctx.restoreGState()
    }

    private func drawHint(_ ctx: CGContext, since: Double, alpha: CGFloat) {
        let f = CGFloat(Self.clamp(since / Self.waitFadeMs)) * alpha
        guard f > 0 else { return }
        drawCentered(ctx, Self.slowHint, font: hintFont, color: muted.withAlphaComponent(f), kern: 0, baseline: hintBaseline)
    }

    /// 가운데 맞춤 한 줄. 자간은 글자 사이에만 둔다(마지막 글자 뒤에 두면 가운데가 한쪽으로 쏠린다)
    private func drawCentered(_ ctx: CGContext, _ text: String, font: UIFont, color: UIColor, kern: CGFloat, baseline: CGFloat) {
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ])
        let length = (text as NSString).length
        if kern != 0, length > 1 {
            attributed.addAttribute(.kern, value: kern, range: NSRange(location: 0, length: length - 1))
        }
        let line = CTLineCreateWithAttributedString(attributed as CFAttributedString)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: centerX - width / 2, y: baseline)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: 도구

    private static let wipeGradient: CGGradient = {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = [CGColor(red: 0, green: 0, blue: 0, alpha: 0), CGColor(red: 0, green: 0, blue: 0, alpha: 1)] as CFArray
        return CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    }()

    /// 빛 띠. 투명 쪽도 같은 색(알파만 0)이라 가장자리에 회색 테가 지지 않는다
    private static let glintGradient: CGGradient = {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let r: CGFloat = 1
        let g: CGFloat = 0xF8 / 255.0
        let b: CGFloat = 0xEC / 255.0
        let clear = CGColor(red: r, green: g, blue: b, alpha: 0)
        let glint = CGColor(red: r, green: g, blue: b, alpha: 1)
        return CGGradient(colorsSpace: space, colors: [clear, glint, clear] as CFArray, locations: [0.3, 0.5, 0.7])!
    }()

    /// 가운데에서 a0 → a1(라디안 · 화면 기준 시계 방향)으로 펼친 부채꼴. 반지름이 그림보다 커서 호는 그림 밖에 있다
    private static func sector(center: CGPoint, radius: CGFloat, from a0: Double, to a1: Double) -> CGPath {
        let path = CGMutablePath()
        path.move(to: center)
        let steps = max(2, Int(((a1 - a0) / (2 * Double.pi / 180)).rounded(.up)))
        for i in 0...steps {
            let a = a0 + (a1 - a0) * Double(i) / Double(steps)
            path.addLine(to: CGPoint(x: center.x + radius * CGFloat(cos(a)), y: center.y + radius * CGFloat(sin(a))))
        }
        path.closeSubpath()
        return path
    }

    /// 웹 로그인 화면과 같은 JetBrains Mono(«Q-ATELIER» 글자만 뗀 조각 · tools/make-assets.py)
    private static func wordmarkFont(size: CGFloat) -> UIFont {
        if let url = Bundle.main.url(forResource: "wordmark-mono", withExtension: "ttf"),
           let provider = CGDataProvider(url: url as CFURL),
           let cgFont = CGFont(provider),
           let name = cgFont.postScriptName as String? {
            // 두 번째부터는 «이미 올렸음» 으로 실패하지만 글꼴은 그대로 쓸 수 있다
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if let font = UIFont(name: name, size: size) { return font }
        }
        appLog.error("글자 조각(wordmark-mono.ttf)을 읽지 못해 시스템 고정폭 글꼴로 그립니다")
        return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func clamp(_ v: Double) -> Double {
        min(max(v, 0), 1)
    }
}

/// 켜는 장면을 그리는 판. 자리와 시간은 LaunchView 가 쥐고 여기서는 그리기만 한다
private final class LaunchCanvas: UIView {
    weak var owner: LaunchView?

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let owner else { return }
        ctx.translateBy(x: -frame.minX, y: -frame.minY)
        owner.render(in: ctx)
    }
}

/// CSS · 안드로이드 PathInterpolator 와 같은 3차 베지어 곡선(끝점 0,0 → 1,1). x 를 주면 y 를 준다
struct CubicBezier {
    private let ax, bx, cx, ay, by, cy: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        cx = 3 * x1
        bx = 3 * (x2 - x1) - cx
        ax = 1 - cx - bx
        cy = 3 * y1
        by = 3 * (y2 - y1) - cy
        ay = 1 - cy - by
    }

    private func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
    private func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
    private func slopeX(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }

    func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        // 뉴턴법으로 먼저 찾고, 기울기가 너무 누우면 반씩 가르기로
        var t = x
        for _ in 0..<8 {
            let err = sampleX(t) - x
            if abs(err) < 1e-6 { return sampleY(t) }
            let d = slopeX(t)
            if abs(d) < 1e-6 { break }
            t -= err / d
        }
        var lo = 0.0
        var hi = 1.0
        t = x
        for _ in 0..<60 {
            let v = sampleX(t)
            if abs(v - x) < 1e-6 { break }
            if x > v { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return sampleY(t)
    }
}
