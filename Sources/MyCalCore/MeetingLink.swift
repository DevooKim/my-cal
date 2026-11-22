import Foundation

public enum MeetingLink {
    private static let regex = try! NSRegularExpression(
        pattern: #"https://(?:[\w-]+\.)*(?:meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com|webex\.com)/[^\s<>"')]+"#,
        options: [.caseInsensitive]
    )

    /// 앞쪽 텍스트를 우선해 처음 발견한 화상회의 링크를 돌려준다.
    public static func find(in texts: [String?]) -> URL? {
        for case let text? in texts {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let matchRange = Range(match.range, in: text),
               let url = URL(string: String(text[matchRange])) {
                return url
            }
        }
        return nil
    }
}
