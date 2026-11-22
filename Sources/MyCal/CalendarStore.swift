import AppKit
import EventKit
import MyCalCore

@MainActor
final class CalendarStore: ObservableObject {
    private let eventStore = EKEventStore()

    @Published private(set) var hasAccess = false
    @Published private(set) var calendars: [EKCalendar] = []
    /// 캘린더 데이터가 바뀔 때마다 증가한다. 화면은 이 값을 구독해 다시 읽는다.
    @Published private(set) var revision = 0

    init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadCalendars() }
        }
    }

    func requestAccess() async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            hasAccess = true
        case .notDetermined:
            hasAccess = (try? await eventStore.requestFullAccessToEvents()) ?? false
        default:
            hasAccess = false
        }
        reloadCalendars()
    }

    func reloadCalendars() {
        calendars = hasAccess
            ? eventStore.calendars(for: .event).sorted {
                ($0.source.title, $0.title) < ($1.source.title, $1.title)
            }
            : []
        revision += 1
    }

    func events(from start: Date, to end: Date, excluding excludedIDs: Set<String>) -> [EKEvent] {
        guard hasAccess else { return [] }
        let targets = calendars.filter { !excludedIDs.contains($0.calendarIdentifier) }
        guard !targets.isEmpty else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: targets)
        return eventStore.events(matching: predicate).sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return (lhs.title ?? "") < (rhs.title ?? "")
        }
    }
}

extension EKEvent {
    /// 반복 일정은 모든 회차가 같은 `eventIdentifier`를 가지므로 시작 시각을 붙여 구분한다.
    var occurrenceID: String {
        "\(eventIdentifier ?? calendarItemIdentifier)@\(startDate.timeIntervalSince1970)"
    }

    private var currentUserStatus: EKParticipantStatus? {
        attendees?.first(where: \.isCurrentUser)?.participantStatus
    }

    var isDeclined: Bool { currentUserStatus == .declined }
    var isPending: Bool { currentUserStatus == .pending }

    /// Google 회의실은 이름 없이 `…@resource.calendar.google.com` 주소를 가진 리소스 참석자로 들어온다.
    var hasGoogleRoom: Bool {
        attendees?.contains { participant in
            (participant.participantType == .resource || participant.participantType == .room)
                && participant.url.absoluteString.hasSuffix("@resource.calendar.google.com")
        } ?? false
    }

    var displayColor: NSColor {
        calendar.map { NSColor(cgColor: $0.cgColor) ?? .systemGray } ?? .systemGray
    }

    /// Google Calendar 웹에서 이 일정을 여는 주소. Google 계정의 캘린더는 제목이 계정 이메일이다.
    /// Google 밖에서 만든 초대처럼 일정 페이지를 알 수 없으면 그 날짜의 주 보기로 연다.
    /// Google 계정 캘린더가 아니면 nil.
    var googleCalendarURL: URL? {
        guard let calendarID = calendar?.title, calendarID.contains("@") else { return nil }
        if let externalID = calendarItemExternalIdentifier,
           let url = GoogleEventLink.url(
               externalID: externalID,
               calendarID: calendarID,
               occurrenceStart: hasRecurrenceRules ? occurrenceDate : nil,
               isAllDay: isAllDay
           ) {
            return url
        }
        return CalendarAppLauncher.googleCalendarURL(for: startDate)
    }

    var meetingURL: URL? {
        MeetingLink.find(in: [url?.absoluteString, location, notes])
    }

    var snapshot: EventSnapshot {
        EventSnapshot(
            id: occurrenceID,
            title: title ?? "",
            start: startDate,
            end: endDate,
            isAllDay: isAllDay,
            isDeclined: isDeclined,
            location: location,
            hasGoogleRoom: hasGoogleRoom
        )
    }
}
