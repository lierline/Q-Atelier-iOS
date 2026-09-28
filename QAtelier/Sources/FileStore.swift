import Foundation
import UniformTypeIdentifiers

/// 받은 파일을 두는 곳. 앱의 문서 폴더라 «파일» 앱의 «나의 iPhone(iPad) › Q-Atelier» 에 보인다
/// (Info.plist 의 UIFileSharingEnabled · LSSupportsOpeningDocumentsInPlace). 안드로이드는 «다운로드/Q-Atelier».
enum FileStore {
    static func folder() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    /// 파일 이름에 쓸 수 없는 글자는 _ 로. 이름이 없으면 Q-Atelier-날짜-시각, 확장자가 없으면 파일 종류에서 붙인다
    /// (안드로이드 MainActivity.fileName 과 같은 규칙)
    static func fileName(_ name: String?, mime: String?) -> String {
        let bad = CharacterSet(charactersIn: "\\/:*?\"<>|")
        var result = (name ?? "")
            .components(separatedBy: bad).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmmss"
            result = "Q-Atelier-" + f.string(from: Date())
        }
        if !result.contains("."), let mime, let ext = UTType(mimeType: mime)?.preferredFilenameExtension {
            result += "." + ext
        }
        return result
    }

    /// 같은 이름이 있으면 «이름 (1).확장자» 처럼 번호를 붙인다(덮어쓰지 않는다)
    static func uniqueURL(for name: String) throws -> URL {
        let dir = try folder()
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = dir.appendingPathComponent(name)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            n += 1
        }
        return candidate
    }
}
