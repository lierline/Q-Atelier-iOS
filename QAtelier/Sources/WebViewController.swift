import QuickLook
import UIKit
import WebKit

/// Q-Atelier iOS 앱의 한 화면(2026-09-28 · 1단계).
///
/// 운영 사이트를 iOS 에 처음부터 들어 있는 웹 화면(WKWebView)으로 띄운다. 안드로이드 앱(WebView · MainActivity)을
/// 옮겼다. 사이트는 서버가 화면을 그리므로 앱 안에 담지 않고 운영 주소를 연다.
///
/// 웹 화면이 스스로 못 하는 일을 여기서 잇는다: 브라우저 안에서 만든 파일 저장(bridge.js) · 서버 파일 받기(WKDownload) ·
/// 인쇄 · 확인 창(alert · confirm · prompt) · 새 창으로 여는 링크 · 우리 사이트 밖 주소는 사파리로 · 끊김 화면 ·
/// 켜는 장면 · 상태 표시줄을 사이트 바탕색에 맞추기. 파일 칸(사진 · 파일 고르기)은 WKWebView 가 스스로 한다.
///
/// 아직 없는 것(애플 개발자 등록 뒤 2단계): 앱 알림 · 지문 · 얼굴 로그인(패스키) · 알림 메일의 링크로 앱 열기.
/// 알림이 없는 동안 사이트의 알림 설정은 «이 브라우저는 알림을 받을 수 없습니다» 로 보인다(window.qatelierApp 을 만들지 않음).
final class WebViewController: UIViewController {
    private enum Keys {
        /// 사이트가 알린 화면 바탕색(#rrggbb). 다음에 켤 때 켜는 장면도 이 색으로 시작한다(안드로이드 look · page_bg)
        static let pageBg = "look.page_bg"
    }

    private static let messageName = "QAtelierApp"

    /// 화면이 바뀌고(commit) 첫 그림 소식이 이만큼 안 오면 켜는 장면을 그냥 걷는다(보조 스크립트가 안 도는 화면 등)
    private static let paintWaitLimit: TimeInterval = 3

    private var webView: WKWebView!
    private var launchView: LaunchView?
    private var hideWork: DispatchWorkItem?
    private var hideDeadline: DispatchTime?
    private var userAgentChecked = false
    /// 사이트가 알린 화면 바탕색. 있으면 앱 바탕 · 상태 표시줄을 이 색에 맞춘다. 없으면 폰의 밤낮을 따른다
    private var pageBg: PageColor?
    /// 마지막으로 연 우리 화면. 끊김 화면의 「다시 시도」 · 웹 엔진이 멈췄을 때 이 주소를 다시 연다
    private var lastURL = AppConfig.home
    private var previewURL: URL?
    private var downloads: [ObjectIdentifier: URL] = [:]
    /// 폰의 밤낮. 화면이 창에 붙기 전(viewDidLoad)의 traitCollection 은 믿을 수 없어 장면(scene)에서 받아 둔다
    private var systemStyle: UIUserInterfaceStyle

    init(systemStyle: UIUserInterfaceStyle) {
        self.systemStyle = systemStyle
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        pageBg = UserDefaults.standard.string(forKey: Keys.pageBg).flatMap { PageColor(hex: $0) }
        lastURL = UIDevice.current.userInterfaceIdiom == .phone ? AppConfig.phoneHome : AppConfig.home
        buildWebView()
        applyColors()
        showLoading(animate: true)
        webView.load(URLRequest(url: lastURL))
    }

    // MARK: 웹 화면

    private func buildWebView() {
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: bridgeSource(), injectionTime: .atDocumentStart, forMainFrameOnly: false))
        controller.add(WeakMessageHandler(self), name: Self.messageName)

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        // 두 손가락 확대(안드로이드 오너 결정 2026-09-26 「확대」). 사이트가 확대를 막아도 확대된다
        config.ignoresViewportScaleLimits = true
        // 전화번호 · 주소를 저절로 링크로 바꾸지 않는다(안드로이드 WebView 와 같게)
        config.dataDetectorTypes = []
        // 사람이 누르지 않고 연 새 창(window.open)도 막지 않는다. 받아서 이 화면에서 연다(createWebViewWith)
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        // 사이트가 앱 안인 줄 알게 브라우저 표시 끝에 QAtelierApp/판 을 붙인다(첫 화면에서 checkUserAgent 로 확인)
        config.applicationNameForUserAgent = AppConfig.userAgentAppName(phone: UIDevice.current.userInterfaceIdiom == .phone)

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        // 왼쪽 끝에서 밀면 앞 화면으로(안드로이드의 뒤로 가기)
        web.allowsBackForwardNavigationGestures = true
        web.allowsLinkPreview = false
        // 첫 그림 전에 흰 바탕이 번쩍이지 않게 투명으로 두고 앱 바탕(사이트 바탕색)이 비치게 한다
        web.isOpaque = false
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif
        // 웹 화면은 안전 영역(상태 표시줄 · 홈 막대 · 노치) 안에 두고, 그 밖은 앱 바탕을 사이트 바탕색으로 칠한다
        // (안드로이드가 시스템 띠 안쪽에 여백을 두고 띠 자리를 사이트 바탕색으로 칠하는 것과 같다)
        view.insertSubview(web, at: 0)
        web.translatesAutoresizingMaskIntoConstraints = false
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: guide.topAnchor),
            web.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
        ])
        webView = web
    }

    /// 앱 안의 bridge.js 에 보조 스크립트를 돌릴 곳(bridgeHosts)을 채워 넣는다. 한 곳(AppConfig)에서만 정한다
    private func bridgeSource() -> String {
        guard let url = Bundle.main.url(forResource: "bridge", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            appLog.fault("앱 안의 bridge.js 를 읽지 못했습니다. 파일 저장 · 인쇄 · 바탕색 맞추기가 동작하지 않습니다")
            return ""
        }
        let hosts = AppConfig.bridgeHosts.sorted().map { "'\($0)'" }.joined(separator: ", ")
        guard source.contains("__BRIDGE_HOSTS__") else {
            appLog.fault("bridge.js 에 __BRIDGE_HOSTS__ 자리가 없습니다")
            return ""
        }
        return source.replacingOccurrences(of: "__BRIDGE_HOSTS__", with: "[\(hosts)]")
    }

    /// 브라우저 표시에 앱 표시가 붙었는지 첫 화면에서 한 번 본다. 빠졌으면 직접 붙여 다시 연다
    /// (앱 이름을 붙이지 않는 화면 방식이 있을 때를 막는 것. 사이트가 앱인 줄 몰라 폰 모드가 안 켜진다)
    private func checkUserAgent() {
        guard !userAgentChecked else { return }
        userAgentChecked = true
        webView.evaluateJavaScript("navigator.userAgent") { [weak self] result, error in
            guard let self else { return }
            guard let ua = result as? String else {
                appLog.error("브라우저 표시를 읽지 못했습니다: \(String(describing: error), privacy: .public)")
                return
            }
            appLog.notice("브라우저 표시: \(ua, privacy: .public)")
            let token = AppConfig.userAgentToken
            if !ua.contains(token) {
                appLog.error("브라우저 표시에 앱 표시가 없어 붙여서 다시 엽니다")
                self.webView.customUserAgent = ua + " " + token
                self.webView.reload()
            }
        }
    }

    // MARK: 색 · 상태 표시줄

    private var currentBg: PageColor {
        if let pageBg { return pageBg }
        return systemStyle == .dark ? Palette.appBgDark : Palette.appBgLight
    }

    /// 앱 바탕(안전 영역 밖 띠 자리 포함)과 웹 화면 뒤를 칠하고 상태 표시줄 글자 밝기를 맞춘다
    private func applyColors() {
        let bg = currentBg.color
        view.backgroundColor = bg
        webView.backgroundColor = bg
        webView.scrollView.backgroundColor = bg
        webView.underPageBackgroundColor = bg
        setNeedsStatusBarAppearanceUpdate()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        guard let pageBg else { return .default }
        return pageBg.isDark ? .lightContent : .darkContent
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        let style = traitCollection.userInterfaceStyle
        guard view.window != nil, style != .unspecified, style != systemStyle else { return }
        systemStyle = style
        if pageBg == nil { applyColors() }
    }

    /// 사이트가 알린 바탕색(#rrggbb). 띠를 그 색으로 칠하고, 다음에 켤 때도 그 색으로 시작하게 기억한다
    private func onPageTheme(_ hex: String) {
        guard let color = PageColor(hex: hex), color != pageBg else { return }
        pageBg = color
        UserDefaults.standard.set(color.hex, forKey: Keys.pageBg)
        applyColors()
        appLog.notice("바탕색: \(color.hex, privacy: .public)")
    }

    // MARK: 켜는 장면

    /// 웹 화면 위를 켜는 장면으로 덮는다. 바탕은 마지막 사이트 바탕색. 앱을 켤 때는 붓이 Q 를 긋는 장면을 돌리고,
    /// 웹 엔진이 멈춰 다시 열 때는 다 그려진 모습만 덮는다
    private func showLoading(animate: Bool) {
        hideWork?.cancel()
        hideWork = nil
        hideDeadline = nil
        launchView?.removeFromSuperview()
        let cover = LaunchView(bg: currentBg, animate: animate)
        view.addSubview(cover)
        cover.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cover.topAnchor.constraint(equalTo: view.topAnchor),
            cover.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            cover.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        launchView = cover
    }

    /// 첫 그림이 보였다. 장면을 끝까지 보여 준 뒤 걷는다. 여러 번 불려도 한 번만 걷는다
    private func hideLoading() {
        hideWork?.cancel()
        hideWork = nil
        hideDeadline = nil
        guard let cover = launchView else { return }
        launchView = nil
        cover.finish { [weak cover] in
            cover?.removeFromSuperview()
            appLog.notice("켜는 장면을 걷었습니다")
        }
    }

    /// 켜는 장면을 걷을 때를 잡는다. 신호가 여럿(첫 그림 · 다 불러옴 · 첫 그림 기다림 한도) 오면 가장 이른 때를 따른다.
    /// 화면이 바뀌었다(commit)는 소식만으로 걷으면 첫 그림 전의 빈 바탕이 잠깐 보여, 보조 스크립트가 알리는
    /// 첫 그림(painted)을 기다린다(안드로이드 onPageCommitVisible 과 같은 때)
    private func hideLoading(after delay: TimeInterval) {
        guard launchView != nil else { return }
        let deadline = DispatchTime.now() + delay
        if let current = hideDeadline, current <= deadline { return }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideLoading() }
        hideWork = work
        hideDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: deadline, execute: work)
    }

    // MARK: 주소

    private func openOutside(_ url: URL) {
        appLog.notice("앱 밖에서 엽니다: \(url.scheme ?? "", privacy: .public)://\(url.host ?? "", privacy: .public)")
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            if !opened { self?.toast("이 주소를 열 앱이 없습니다") }
        }
    }

    /// 새 창(target=_blank · window.open)으로 열려던 것. 앱에는 창이 하나라 이 화면에서 열거나 밖으로 넘긴다
    private func openNewWindow(_ request: URLRequest) {
        guard let url = request.url else { return }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "blob" || scheme == "data" {
            // 브라우저 안에서 만든 파일을 새 창으로 열려 했다. 보조 스크립트로 읽어 저장한다
            webView.evaluateJavaScript(
                "window.__qatelierSave && window.__qatelierSave(\(Self.jsString(url.absoluteString)), '')",
                completionHandler: nil)
        } else if AppConfig.isOurs(url) {
            webView.load(request)
        } else if scheme == "about" {
            // 빈 새 창은 열 곳이 없다
        } else {
            openOutside(url)
        }
    }

    private var offlineFile: URL? {
        Bundle.main.url(forResource: "offline", withExtension: "html")
    }

    /// 끊김 화면도 마지막 사이트 바탕(밝음 · 어두움)을 따른다(안드로이드 2.4.0). 모르면 폰의 밤낮(offline.html)
    private func showOffline() {
        guard let file = offlineFile else { return }
        var parts = URLComponents(url: file, resolvingAgainstBaseURL: false)
        if let pageBg { parts?.fragment = pageBg.isDark ? "dark" : "light" }
        webView.loadFileURL(parts?.url ?? file, allowingReadAccessTo: file)
    }

    private static let networkErrors: Set<Int> = [
        NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
        NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed,
        NSURLErrorSecureConnectionFailed, NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed,
        NSURLErrorCannotLoadFromNetwork,
    ]

    private func handleLoadError(_ error: Error, provisional: Bool) {
        let e = error as NSError
        appLog.error("불러오기 실패(\(e.domain, privacy: .public) \(e.code, privacy: .public)): \(e.localizedDescription, privacy: .public)")
        let network = e.domain == NSURLErrorDomain && e.code != NSURLErrorCancelled
        if network && (provisional || Self.networkErrors.contains(e.code)) {
            showOffline()
            return
        }
        // 받기로 넘긴 화면(WebKit 102) · 취소 등. 첫 화면에서 이렇게 끝나도 켜는 장면이 남지 않게 걷는다
        if !webView.isLoading { hideLoading() }
    }

    private static func describe(_ url: URL?) -> String {
        guard let url else { return "(없음)" }
        if url.isFileURL { return "앱 안 " + url.lastPathComponent }
        return (url.host ?? "") + url.path
    }

    /// JS 문자열로 안전하게 감싼다(따옴표 · 줄바꿈 등)
    private static func jsString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8) else { return "''" }
        return text
    }

    // MARK: 파일 · 인쇄

    /// 브라우저 안에서 만든 파일을 문서 폴더(파일 앱의 Q-Atelier)에 저장하고 미리 보기로 연다
    private func saveFile(base64: String, mime: String, name: String) {
        guard let bytes = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            toast("파일을 읽지 못했습니다")
            return
        }
        let type = mime.isEmpty ? "application/octet-stream" : mime
        do {
            let target = try FileStore.uniqueURL(for: FileStore.fileName(name, mime: type))
            try bytes.write(to: target, options: .atomic)
            appLog.notice("저장했습니다: \(target.lastPathComponent, privacy: .public) (\(bytes.count, privacy: .public) 바이트)")
            toast("저장했습니다: \(target.lastPathComponent) (파일 앱의 Q-Atelier 폴더)")
            preview(target)
        } catch {
            appLog.error("저장 실패: \(error.localizedDescription, privacy: .public)")
            toast("파일을 저장하지 못했습니다")
        }
    }

    private func preview(_ url: URL) {
        previewURL = url
        let viewer = QLPreviewController()
        viewer.dataSource = self
        topController().present(viewer, animated: true)
    }

    private func printPage(title: String) {
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = title.isEmpty ? "Q-Atelier" : title
        let printer = UIPrintInteractionController.shared
        printer.printInfo = info
        printer.printFormatter = webView.viewPrintFormatter()
        if traitCollection.userInterfaceIdiom == .pad {
            let anchor = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            printer.present(from: anchor, in: view, animated: true, completionHandler: nil)
        } else {
            printer.present(animated: true, completionHandler: nil)
        }
    }

    // MARK: 작은 도구

    private func topController() -> UIViewController {
        var top: UIViewController = self
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }

    /// 확인 창을 띄운다. 띄울 수 없으면 사이트가 멈추지 않게 바로 답한다(WebKit 은 답이 꼭 한 번 오기를 기다린다)
    private func presentDialog(_ alert: UIAlertController, orElse fallback: @escaping () -> Void) {
        let top = topController()
        guard top.view.window != nil, !(top is UIAlertController) else {
            fallback()
            return
        }
        top.present(alert, animated: true)
    }

    private func toast(_ text: String) {
        ToastView.show(text, in: view)
    }
}

// MARK: - 화면 이동

extension WebViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == AppConfig.retryScheme {
            decisionHandler(.cancel)
            if url.host?.lowercased() == AppConfig.retryHost { webView.load(URLRequest(url: lastURL)) }
            return
        }
        if navigationAction.targetFrame == nil {
            decisionHandler(.cancel)
            openNewWindow(navigationAction.request)
            return
        }
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        if scheme == "blob" || scheme == "data" || scheme == "about" {
            decisionHandler(.allow)
            return
        }
        if scheme == "file" {
            decisionHandler(url.path == offlineFile?.path ? .allow : .cancel)
            return
        }
        let mainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if AppConfig.isOurs(url) {
            if mainFrame && AppConfig.isBridgeHost(url) { lastURL = url }
            decisionHandler(.allow)
            return
        }
        if !mainFrame {
            // 화면 안의 작은 틀(iframe)은 그대로 둔다
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        openOutside(url)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.isForMainFrame && Self.shouldDownload(navigationResponse) {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    /// 화면에 띄우지 않고 받을 것: 첨부(Content-Disposition: attachment) · 웹 화면이 못 보이는 종류 ·
    /// 첨부 파일 저장소에서 온 파일(PDF 도 앱 화면을 갈아엎지 않고 받아서 미리 보기로 연다)
    private static func shouldDownload(_ navigationResponse: WKNavigationResponse) -> Bool {
        if !navigationResponse.canShowMIMEType { return true }
        let response = navigationResponse.response
        if let http = response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().hasPrefix("attachment") {
            return true
        }
        if let url = response.url, url.host?.lowercased() == AppConfig.storageHost, url.path.hasPrefix("/storage/") {
            return true
        }
        return false
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
        restoreLastURL()
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
        restoreLastURL()
    }

    /// 받기로 넘어간 주소는 «마지막 화면» 이 아니다. 보이는 화면으로 되돌린다(다시 시도가 파일을 또 받지 않게)
    private func restoreLastURL() {
        if let url = webView.url, AppConfig.isBridgeHost(url) { lastURL = url }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let url = webView.url, AppConfig.isBridgeHost(url) { lastURL = url }
        appLog.notice("화면: \(Self.describe(webView.url), privacy: .public)")
        checkUserAgent()
        hideLoading(after: Self.paintWaitLimit)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        appLog.notice("다 불러옴: \(Self.describe(webView.url), privacy: .public)")
        hideLoading(after: 0.1)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadError(error, provisional: true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadError(error, provisional: false)
    }

    /// 웹 엔진이 멈추거나 메모리가 모자라 iOS 가 거둬 가면 화면이 하얗게 빈다. 보던 화면을 다시 연다.
    /// 로그인은 쿠키에 있어 그대로다(안드로이드 onRenderProcessGone)
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        appLog.error("웹 엔진이 멈췄습니다. 보던 화면을 다시 엽니다")
        showLoading(animate: false)
        webView.load(URLRequest(url: lastURL))
    }
}

// MARK: - 새 창 · 확인 창

extension WebViewController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        openNewWindow(navigationAction.request)
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in completionHandler() })
        presentDialog(alert) { completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in completionHandler(true) })
        presentDialog(alert) { completionHandler(false) }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text ?? "")
        })
        presentDialog(alert) { completionHandler(nil) }
    }
}

// MARK: - 서버 파일 받기

extension WebViewController: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        do {
            let target = try FileStore.uniqueURL(for: FileStore.fileName(suggestedFilename, mime: response.mimeType))
            downloads[ObjectIdentifier(download)] = target
            toast("받는 중: \(target.lastPathComponent)")
            completionHandler(target)
        } catch {
            appLog.error("받을 자리를 만들지 못했습니다: \(error.localizedDescription, privacy: .public)")
            toast("파일을 저장하지 못했습니다")
            completionHandler(nil)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let target = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        appLog.notice("받았습니다: \(target.lastPathComponent, privacy: .public)")
        toast("저장했습니다: \(target.lastPathComponent) (파일 앱의 Q-Atelier 폴더)")
        preview(target)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads.removeValue(forKey: ObjectIdentifier(download))
        appLog.error("받기 실패: \(error.localizedDescription, privacy: .public)")
        toast("파일을 받지 못했습니다. 다시 눌러 주십시오")
    }
}

// MARK: - 보조 스크립트(bridge.js)가 보낸 말

extension WebViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // 우리 화면이 보낸 말만 듣는다. 스크립트도 스스로 멈추지만 앱이 한 번 더 본다
        let origin = message.frameInfo.securityOrigin
        guard origin.protocol == "https", AppConfig.bridgeHosts.contains(origin.host.lowercased()),
              origin.port == 0 || origin.port == 443 else {
            appLog.error("우리 화면이 아닌 곳에서 온 말을 버렸습니다: \(origin.host, privacy: .public)")
            return
        }
        guard let text = message.body as? String, let data = text.data(using: .utf8),
              let m = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            appLog.error("읽지 못한 말을 버렸습니다")
            return
        }
        let kind = m["kind"] as? String ?? ""
        switch kind {
        case "save":
            saveFile(base64: m["data"] as? String ?? "", mime: m["type"] as? String ?? "", name: m["name"] as? String ?? "")
        case "save-failed":
            appLog.error("파일 읽기 실패: \(m["reason"] as? String ?? "", privacy: .public)")
            toast("파일을 받지 못했습니다. 다시 눌러 주십시오")
        case "print":
            printPage(title: m["title"] as? String ?? "")
        case "theme":
            onPageTheme(m["bg"] as? String ?? "")
        case "painted":
            // 첫 그림이 화면에 나갔다. 안쪽 틀(iframe)의 첫 그림은 켜는 장면과 상관없다
            guard message.frameInfo.isMainFrame else { return }
            appLog.notice("첫 그림")
            hideLoading(after: 0.05)
        default:
            appLog.error("모르는 말: \(kind, privacy: .public)")
        }
    }
}

// MARK: - 미리 보기

extension WebViewController: QLPreviewControllerDataSource {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        (previewURL ?? URL(fileURLWithPath: NSTemporaryDirectory())) as NSURL
    }
}

/// 말 받는 곳을 약하게 쥔다. WKUserContentController 는 받는 곳을 강하게 쥐어, 화면을 바로 넘기면 서로 놓지 못한다
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
