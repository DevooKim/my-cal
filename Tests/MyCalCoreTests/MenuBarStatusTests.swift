import Foundation
import Testing
@testable import MyCalCore

private let base = Date(timeIntervalSince1970: 1_800_000_000)

private func event(
    _ id: String,
    start: TimeInterval,
    end: TimeInterval,
    allDay: Bool = false,
    declined: Bool = false
) -> EventSnapshot {
    EventSnapshot(
        id: id,
        title: id,
        start: base.addingTimeInterval(start * 60),
        end: base.addingTimeInterval(end * 60),
        isAllDay: allDay,
        isDeclined: declined
    )
}

@Suite struct MenuBarStatusResolverTests {
    @Test func 진행_중인_일정을_다가오는_일정보다_우선한다() {
        let events = [event("진행", start: -10, end: 20), event("다음", start: 5, end: 30)]
        let status = MenuBarStatusResolver.resolve(events: events, now: base, leadTime: 3600)
        #expect(status?.event.id == "진행")
        #expect(status?.phase == .ongoing(remaining: 20 * 60))
    }

    @Test func 진행_중인_일정이_겹치면_가장_늦게_시작한_일정을_고른다() {
        let events = [event("긴 일정", start: -120, end: 120), event("방금 시작", start: -5, end: 25)]
        let status = MenuBarStatusResolver.resolve(events: events, now: base, leadTime: 0)
        #expect(status?.event.id == "방금 시작")
    }

    @Test func 시작_시각이_같으면_먼저_끝나는_일정을_고른다() {
        let events = [event("길다", start: -5, end: 60), event("짧다", start: -5, end: 25)]
        let status = MenuBarStatusResolver.resolve(events: events, now: base, leadTime: 0)
        #expect(status?.event.id == "짧다")
    }

    @Test func 표시_시작_시간_안에_있는_가장_가까운_일정을_고른다() {
        let events = [event("나중", start: 50, end: 60), event("먼저", start: 30, end: 40)]
        let status = MenuBarStatusResolver.resolve(events: events, now: base, leadTime: 3600)
        #expect(status?.event.id == "먼저")
        #expect(status?.phase == .upcoming(startsIn: 30 * 60))
    }

    @Test func 표시_시작_시간보다_먼_일정은_보여주지_않는다() {
        let events = [event("먼 일정", start: 61, end: 90)]
        #expect(MenuBarStatusResolver.resolve(events: events, now: base, leadTime: 3600) == nil)
    }

    @Test func 종일_일정과_거절한_일정은_제외한다() {
        let events = [
            event("종일", start: -60, end: 1380, allDay: true),
            event("거절", start: -10, end: 20, declined: true),
        ]
        #expect(MenuBarStatusResolver.resolve(events: events, now: base, leadTime: 3600) == nil)
    }

    @Test func 길이가_없는_일정은_표시하지_않고_시작_시각이_같으면_첫_일정을_고른다() {
        let events = [
            event("길이 없음", start: 1, end: 1),
            event("첫 일정", start: 10, end: 20),
            event("두 번째 일정", start: 10, end: 15),
        ]
        #expect(MenuBarStatusResolver.resolve(events: events, now: base, leadTime: 600)?.event.id == "첫 일정")
    }

    @Test func 끝난_시각에는_진행_중으로_보지_않는다() {
        let events = [event("끝남", start: -30, end: 0)]
        #expect(MenuBarStatusResolver.resolve(events: events, now: base, leadTime: 3600) == nil)
    }
}

@Suite struct MenuBarTextTests {
    @Test func 남은_시간을_분_단위로_올림한다() {
        #expect(MenuBarText.duration(59) == "1분")
        #expect(MenuBarText.duration(16 * 60 + 1) == "17분")
        #expect(MenuBarText.duration(60 * 60) == "1시간")
        #expect(MenuBarText.duration(85 * 60) == "1시간 25분")
    }

    @Test func 긴_제목은_말줄임표로_자른다() {
        #expect(MenuBarText.truncate("가나다라마바사", to: 3) == "가나다…")
        #expect(MenuBarText.truncate("  짧음 ", to: 10) == "짧음")
        #expect(MenuBarText.truncate("   ", to: 10) == "(제목 없음)")
    }

    @Test func 진행_중과_예정_문구를_만든다() {
        let item = event("회의", start: 0, end: 30)
        #expect(MenuBarText.text(for: .init(event: item, phase: .ongoing(remaining: 17 * 60)), maxTitleLength: 30) == "회의 · 17분 남음")
        #expect(MenuBarText.text(for: .init(event: item, phase: .upcoming(startsIn: 90 * 60)), maxTitleLength: 30) == "회의 · 1시간 30분 후")
    }

    @Test func 위치를_포함하면_제목과_남은_시간_사이에_넣는다() {
        let item = EventSnapshot(
            id: "회의", title: "회의", start: base, end: base.addingTimeInterval(1800),
            isAllDay: false, isDeclined: false, location: "건물 A-2층-동관-예시실 (10)", hasGoogleRoom: true
        )
        let status = MenuBarStatus(event: item, phase: .ongoing(remaining: 17 * 60))
        #expect(MenuBarText.text(for: status, maxTitleLength: 30, includeLocation: true) == "회의 · 예시실 · 17분 남음")
        #expect(MenuBarText.text(for: status, maxTitleLength: 30, includeLocation: false) == "회의 · 17분 남음")
    }

    @Test func 위치가_없으면_위치를_포함해도_생략한다() {
        let status = MenuBarStatus(event: event("회의", start: 0, end: 30), phase: .upcoming(startsIn: 300))
        #expect(MenuBarText.text(for: status, maxTitleLength: 30, includeLocation: true) == "회의 · 5분 후")
    }
}

@Suite struct ShortLocationTests {
    @Test func 구글_회의실_이름에서_건물_층_수용_인원_기능을_뗀다() {
        #expect(MenuBarText.shortLocation("건물 A-2층-동관-1. 대회의실 (10) [화상 회의]", hasGoogleRoom: true) == "1. 대회의실")
        #expect(MenuBarText.shortLocation("Tower A-4-Mercury (8)", hasGoogleRoom: true) == "Mercury")
    }

    @Test func 구글_회의실이_여러_개면_첫_회의실과_나머지_개수를_보여준다() {
        let location = "건물 A-2층-예시실 1 (8) [화상 회의], 건물 B-3층-예시실 2 (8) [화상 회의], 건물 B-3층-예시실 3 (8)"
        #expect(MenuBarText.shortLocation(location, hasGoogleRoom: true) == "예시실 1 외 2")
    }

    @Test func 회의실이_아닌_위치는_해석하지_않고_길면_자른다() {
        #expect(MenuBarText.shortLocation("1, 대한민국 예시도 예시시 예시구 예시로100번길 1", hasGoogleRoom: false) == "1, 대한민국 예시도 예시시 예시구 …")
        #expect(MenuBarText.shortLocation("A-3 회의실", hasGoogleRoom: false) == "A-3 회의실")
    }

    @Test func URL이거나_비어_있으면_위치로_보지_않는다() {
        #expect(MenuBarText.shortLocation("https://meet.google.com/abc-defg-hij", hasGoogleRoom: false) == nil)
        #expect(MenuBarText.shortLocation("  ", hasGoogleRoom: true) == nil)
        #expect(MenuBarText.shortLocation(nil, hasGoogleRoom: false) == nil)
    }
}

@Suite struct MeetingLinkTests {
    @Test func 설명에_있는_화상회의_링크를_찾는다() {
        let notes = "Join with Google Meet: https://meet.google.com/abc-defg-hij\nOr dial: +1 555"
        #expect(MeetingLink.find(in: [nil, "3층 회의실", notes])?.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test func 줌_하위_도메인을_인식한다() {
        #expect(MeetingLink.find(in: ["<https://us02web.zoom.us/j/123?pwd=x>"])?.absoluteString == "https://us02web.zoom.us/j/123?pwd=x")
    }

    @Test func 화상회의가_아닌_링크는_무시한다() {
        #expect(MeetingLink.find(in: ["https://example.com/meet"]) == nil)
    }
}

@Suite struct GoogleEventLinkTests {
    private func decodedEID(_ url: URL?) -> String? {
        guard let url,
              let eid = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        else { return nil }
        let padded = eid + String(repeating: "=", count: (4 - eid.count % 4) % 4)
        return Data(base64Encoded: padded).flatMap { String(data: $0, encoding: .utf8) }
    }

    @Test func 일반_일정은_이벤트_ID와_캘린더_ID로_eid를_만든다() {
        let url = GoogleEventLink.url(
            externalID: "event1abc@google.com",
            calendarID: "me@example.com", occurrenceStart: nil, isAllDay: false
        )
        #expect(url?.absoluteString.hasPrefix("https://calendar.google.com/calendar/event?eid=") == true)
        #expect(decodedEID(url) == "event1abc me@example.com")
    }

    @Test func 따로_수정한_회차는_RID를_UTC_시작_시각으로_바꿔_붙인다() {
        let url = GoogleEventLink.url(
            externalID: "event2abc@google.com/RID=814759200",
            calendarID: "me@example.com", occurrenceStart: nil, isAllDay: false
        )
        #expect(decodedEID(url) == "event2abc_20261027T020000Z me@example.com")
    }

    @Test func 나뉜_반복_일정의_ID도_그대로_쓴다() {
        let url = GoogleEventLink.url(
            externalID: "series3abc_R20260804T050000@google.com/RID=814770000",
            calendarID: "me@example.com", occurrenceStart: nil, isAllDay: false
        )
        #expect(decodedEID(url) == "series3abc_R20260804T050000_20261027T050000Z me@example.com")
    }

    @Test func 수정하지_않은_반복_회차는_회차_시작_시각을_붙인다() {
        let start = Date(timeIntervalSinceReferenceDate: 814_932_000)
        let url = GoogleEventLink.url(
            externalID: "event4abc@google.com",
            calendarID: "me@example.com", occurrenceStart: start, isAllDay: false
        )
        #expect(decodedEID(url) == "event4abc_20261029T020000Z me@example.com")
    }

    @Test func 종일_반복_회차는_날짜만_붙인다() {
        let seoul = TimeZone(identifier: "Asia/Seoul")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29))!
        let url = GoogleEventLink.url(
            externalID: "abc@google.com", calendarID: "me@example.com",
            occurrenceStart: start, isAllDay: true, timeZone: seoul
        )
        #expect(decodedEID(url) == "abc_20261029 me@example.com")
    }

    @Test func eid의_슬래시와_패딩을_쿼리에_그대로_두지_않는다() {
        // "??? me@example.com"의 base64는 "Pz8/"로 시작해 슬래시가 들어간다.
        let url = GoogleEventLink.url(
            externalID: "???@google.com", calendarID: "me@example.com", occurrenceStart: nil, isAllDay: false
        )
        let eid = url?.query?.replacingOccurrences(of: "eid=", with: "") ?? ""
        #expect(eid.hasPrefix("Pz8%2F"))
        #expect(!eid.contains("/") && !eid.contains("+") && !eid.contains("="))
        #expect(decodedEID(url) == "??? me@example.com")
    }

    @Test func 구글에서_만들지_않은_일정이나_이메일이_아닌_캘린더는_nil() {
        #expect(GoogleEventLink.url(externalID: "040000008200E00074C5B7101A82E008", calendarID: "me@example.com", occurrenceStart: nil, isAllDay: false) == nil)
        #expect(GoogleEventLink.url(externalID: "abc@google.com", calendarID: "팀 공유 캘린더", occurrenceStart: nil, isAllDay: false) == nil)
    }
}
