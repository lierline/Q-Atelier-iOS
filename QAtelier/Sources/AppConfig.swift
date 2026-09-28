import Foundation
import os

/// 앱이 여는 주소와 앱 안에서 다루는 곳. 안드로이드 앱(MainActivity)과 같은 값이다.
enum AppConfig {
    /// 앱을 열면 가는 화면(패드). 로그인이 안 되어 있으면 사이트가 로그인 화면으로 보낸다
    static let home = URL(string: "https://www.qatelier.co.kr/dashboard")!

    /// 폰은 결재함부터 연다(오너 결정 2026-09-27 「폰은 결재만」). 사이트 lib/nav/phone-mode.ts 의 PHONE_HOME 과 같다.
    /// 사이트는 짧은 변 600 미만을 폰으로 본다. 아이폰은 가장 큰 기종도 짧은 변이 440pt, 아이패드는 가장 작은
    /// 기종도 744pt 라 기기 종류로 갈라도 같다.
    static let phoneHome = URL(string: "https://www.qatelier.co.kr/approve")!

    /// 첨부 파일 저장소. 여기서 오는 파일은 앱 화면을 갈아엎지 않고 받아서 미리 보기로 연다
    static let storageHost = "uyxmxmagsbontxreyelo.supabase.co"

    /// 앱 안에서 여는 주소. 나머지는 사파리 · 다른 앱으로 넘긴다
    static let ourHosts: Set<String> = ["www.qatelier.co.kr", "qatelier.co.kr", "atelier.medqraft.app", storageHost]

    /// 보조 스크립트(bridge.js)가 돌고 앱과 말을 주고받는 곳. 첨부 파일 저장소에는 열지 않는다
    static let bridgeHosts: Set<String> = ["www.qatelier.co.kr", "qatelier.co.kr", "atelier.medqraft.app"]

    /// 끊김 화면의 「다시 시도」 가 가는 주소(qatelier-app://retry). 앱이 가로채 마지막 화면을 다시 연다
    static let retryScheme = "qatelier-app"
    static let retryHost = "retry"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 사이트가 앱 안인 줄 아는 표시(사이트 lib/nav/phone-mode.ts 의 isAppUserAgent · 안드로이드와 같은 글자)
    static var userAgentToken: String { "QAtelierApp/" + version }

    /// 웹 엔진이 브라우저 표시 끝에 붙이는 앱 이름(WKWebViewConfiguration.applicationNameForUserAgent).
    /// 폰은 iOS 웹 화면의 기본값(Mobile/15E148)을 남기고 그 뒤에 붙인다. 패드는 데스크톱 방식이라 기본 표시에
    /// Mobile 이 없으니 앱 표시만 붙인다(안드로이드도 폰에만 Mobile 이 있다).
    /// 웹 화면에 기본 표시를 물어본 뒤 붙이면 첫 화면을 여는 일이 그만큼 늦어져 이 길을 쓴다
    static func userAgentAppName(phone: Bool) -> String {
        phone ? "Mobile/15E148 " + userAgentToken : userAgentToken
    }

    static func isOurs(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return ourHosts.contains(host)
    }

    static func isBridgeHost(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return bridgeHosts.contains(host)
    }
}

/// 앱 기록. 깃허브 맥의 시뮬레이터 점검이 이 이름(subsystem)으로 걸러 읽는다(scripts/shoot.sh)
let appLog = Logger(subsystem: "app.medqraft.qatelier", category: "app")
