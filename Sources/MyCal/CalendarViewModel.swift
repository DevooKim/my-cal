import AppKit
import Combine
import EventKit

struct EventItem: Identifiable {
    let id: String
    let title: String
    let location: String?
    let start: Date
    let end: Date
    let isAllDay: Bool
    let isPending: Bool
    let isDeclined: Bool
    let color: NSColor
    let meetingURL: URL?
    let source: EKEvent

    init(_ event: EKEvent) {
        source = event
        id = event.occurrenceID
        title = (event.title ?? "").isEmpty ? "(제목 없음)" : event.title!
        location = event.location?.isEmpty == false ? event.location : nil
        start = event.startDate
        end = event.endDate
        isAllDay = event.isAllDay
        isPending = event.isPending
        isDeclined = event.isDeclined
        color = event.displayColor
        meetingURL = event.meetingURL
    }
}

struct DaySection: Identifiable {
    let day: Date
    let events: [EventItem]
    var id: Date { day }
}

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published private(set) var displayedMonth: Date
    @Published private(set) var selectedDate: Date
    /// 날짜(그날 0시)별로 달력 칸 아래에 찍을 캘린더 색. 한 칸에 최대 3개.
    @Published private(set) var dayMarkers: [Date: [NSColor]] = [:]
    @Published private(set) var sections: [DaySection] = []
    /// 목록에서 마우스를 올린 일정. 달력에서 이 일정이 걸친 날짜를 일정 색으로 칠한다.
    @Published private(set) var hoveredEvent: EventItem?
    @Published private(set) var hoveredDays: Set<Date> = []
    /// 상세 정보를 보고 있는 일정. nil이면 목록을 보여준다.
    @Published private(set) var detailEvent: EventItem?

    private let store: CalendarStore
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

    init(store: CalendarStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        let today = Date()
        displayedMonth = Self.firstOfMonth(today, in: .current)
        selectedDate = Calendar.current.startOfDay(for: today)

        Publishers.Merge4(
            settings.$firstWeekday.removeDuplicates().dropFirst().map { _ in () },
            settings.$daysToShow.removeDuplicates().dropFirst().map { _ in () },
            settings.$hiddenCalendarIDs.removeDuplicates().dropFirst().map { _ in () },
            store.$revision.map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.reload() }
        .store(in: &cancellables)
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.timeZone = .current
        calendar.firstWeekday = settings.firstWeekday
        return calendar
    }

    /// 6주 × 7일 고정 격자. 달마다 높이가 바뀌지 않게 항상 42칸을 채운다.
    var gridDays: [Date] {
        let calendar = calendar
        let weekday = calendar.component(.weekday, from: displayedMonth)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: displayedMonth)!
        return (0..<42).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    /// 화면 순서대로 정렬한 요일 머리글. `weekday`는 `Calendar`와 같이 1 = 일요일, 7 = 토요일이다.
    var weekdayHeaders: [(weekday: Int, symbol: String)] {
        let symbols = calendar.veryShortWeekdaySymbols
        return (0..<7).map { offset in
            let weekday = (settings.firstWeekday - 1 + offset) % 7 + 1
            return (weekday, symbols[weekday - 1])
        }
    }

    /// 다음 행의 진입 이벤트가 이전 행의 이탈 이벤트보다 먼저 올 수 있으므로,
    /// 이탈은 지금 강조 중인 일정에서 온 것만 반영한다.
    func setHovering(_ hovering: Bool, over event: EventItem) {
        guard detailEvent == nil else { return }
        if hovering {
            hoveredEvent = event
            let end = max(event.end, event.start.addingTimeInterval(1))
            hoveredDays = Set(Self.days(from: event.start, to: end, in: calendar))
        } else if hoveredEvent?.id == event.id {
            clearHover()
        }
    }

    private func clearHover() {
        hoveredEvent = nil
        hoveredDays = []
    }

    /// 상세 화면을 보는 동안에는 달력에 그 일정이 걸친 날짜를 계속 칠해 둔다.
    func showDetail(_ event: EventItem) {
        setHovering(true, over: event)
        detailEvent = event
    }

    func closeDetail() {
        detailEvent = nil
        clearHover()
    }

    func showToday() {
        closeDetail()
        let today = Date()
        displayedMonth = Self.firstOfMonth(today, in: calendar)
        selectedDate = calendar.startOfDay(for: today)
        reload()
    }

    func moveMonth(by value: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth)!
        reload()
    }

    func select(_ day: Date) {
        selectedDate = calendar.startOfDay(for: day)
        let month = Self.firstOfMonth(day, in: calendar)
        if month != displayedMonth { displayedMonth = month }
        reload()
    }

    func openCalendarApp() {
        CalendarAppLauncher.open(with: settings, date: selectedDate)
    }

    func reload() {
        let calendar = calendar
        let hidden = settings.hiddenCalendarIDs

        let days = gridDays
        let gridStart = days.first!
        let gridEnd = calendar.date(byAdding: .day, value: 1, to: days.last!)!
        let listStart = selectedDate
        let listEnd = calendar.date(byAdding: .day, value: settings.daysToShow, to: listStart)!

        let gridEvents = store.events(from: gridStart, to: gridEnd, excluding: hidden)
        let listEvents = listStart >= gridStart && listEnd <= gridEnd
            ? gridEvents
            : store.events(from: listStart, to: listEnd, excluding: hidden)

        var markers: [Date: [NSColor]] = [:]
        for event in gridEvents {
            let color = event.displayColor
            for day in Self.days(from: max(event.startDate, gridStart), to: min(event.endDate, gridEnd), in: calendar) {
                if markers[day, default: []].count < 3, !markers[day, default: []].contains(color) {
                    markers[day, default: []].append(color)
                }
            }
        }
        dayMarkers = markers

        let items = listEvents
            .filter { $0.startDate < listEnd && $0.endDate > listStart }
            .map(EventItem.init)
        sections = Self.days(from: listStart, to: listEnd, in: calendar).compactMap { day in
            let next = calendar.date(byAdding: .day, value: 1, to: day)!
            let events = items.filter { $0.start < next && $0.end > day }
            return events.isEmpty ? nil : DaySection(day: day, events: events)
        }
    }

    private static func firstOfMonth(_ date: Date, in calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }

    /// `start`부터 `end` 직전까지 걸친 날들의 0시 목록. 종일 일정의 `endDate`는 마지막 날 23:59:59이고,
    /// 자정에 끝나는 시간 일정은 다음 날에 표시하지 않는다.
    private static func days(from start: Date, to end: Date, in calendar: Calendar) -> [Date] {
        var day = calendar.startOfDay(for: start)
        var result: [Date] = []
        while day < end {
            result.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }
}
