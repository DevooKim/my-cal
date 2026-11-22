import Foundation

public enum GoogleEventLink {
    private static let googleUIDSuffix = "@google.com"
    private static let recurrenceIDMarker = "/RID="

    /// EventKit이 Google 일정에 붙이는 외부 ID로 Google Calendar 웹의 일정 페이지 주소를 만든다.
    ///
    /// 외부 ID는 "<이벤트 ID>@google.com" 형태이고, 반복 일정에서 따로 수정한 회차는 뒤에
    /// "/RID=<원래 시작 시각, 2001-01-01 기준 초>"가 붙는다. 수정하지 않은 반복 회차는 RID가 없으므로
    /// `occurrenceStart`로 회차를 지정한다. Google에서 만들지 않은 일정이거나 `calendarID`가
    /// 이메일 형태가 아니면 페이지 주소를 알 수 없어 nil을 돌려준다.
    public static func url(
        externalID: String,
        calendarID: String,
        occurrenceStart: Date?,
        isAllDay: Bool,
        timeZone: TimeZone = .current
    ) -> URL? {
        let parts = externalID.components(separatedBy: recurrenceIDMarker)
        let uid = parts[0]
        guard uid.hasSuffix(googleUIDSuffix), calendarID.contains("@") else { return nil }

        var eventID = String(uid.dropLast(googleUIDSuffix.count))
        let originalStart = parts.count > 1
            ? Double(parts[1]).map(Date.init(timeIntervalSinceReferenceDate:))
            : occurrenceStart
        if let originalStart {
            eventID += "_" + instanceSuffix(originalStart, isAllDay: isAllDay, timeZone: timeZone)
        }

        let eid = Data("\(eventID) \(calendarID)".utf8)
            .base64EncodedString()
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        // base64의 +와 /가 쿼리에서 다른 뜻으로 읽히지 않도록 영숫자 외에는 모두 인코딩한다.
        guard let encoded = eid.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URL(string: "https://calendar.google.com/calendar/event?eid=\(encoded)")
    }

    /// Google 반복 일정 회차 ID의 접미사. 시간 일정은 UTC 시작 시각, 종일 일정은 날짜만 쓴다.
    private static func instanceSuffix(_ start: Date, isAllDay: Bool, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if isAllDay {
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyyMMdd"
        } else {
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        }
        return formatter.string(from: start)
    }
}
