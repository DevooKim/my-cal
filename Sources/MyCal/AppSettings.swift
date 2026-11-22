import Foundation

/// 팝오버의 캘린더 버튼을 눌렀을 때 열 대상.
enum CalendarAppTarget: String {
    case system
    case google
    case custom
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let showEventInMenuBar = "showEventInMenuBar"
        static let showLocationInMenuBar = "showLocationInMenuBar"
        static let leadMinutes = "leadMinutes"
        static let maxTitleLength = "maxTitleLength"
        static let daysToShow = "daysToShow"
        static let firstWeekday = "firstWeekday"
        static let hiddenCalendarIDs = "hiddenCalendarIDs"
        static let menuBarExcludedCalendarIDs = "menuBarExcludedCalendarIDs"
        static let calendarAppTarget = "calendarAppTarget"
        static let customCalendarAppPath = "customCalendarAppPath"
    }

    private let defaults = UserDefaults.standard

    @Published var showEventInMenuBar: Bool {
        didSet { defaults.set(showEventInMenuBar, forKey: Key.showEventInMenuBar) }
    }
    @Published var showLocationInMenuBar: Bool {
        didSet { defaults.set(showLocationInMenuBar, forKey: Key.showLocationInMenuBar) }
    }
    /// 일정 시작 몇 분 전부터 메뉴바에 제목을 보여줄지. 0이면 진행 중일 때만 보여준다.
    @Published var leadMinutes: Int {
        didSet { defaults.set(leadMinutes, forKey: Key.leadMinutes) }
    }
    @Published var maxTitleLength: Int {
        didSet { defaults.set(maxTitleLength, forKey: Key.maxTitleLength) }
    }
    @Published var daysToShow: Int {
        didSet { defaults.set(daysToShow, forKey: Key.daysToShow) }
    }
    /// `Calendar.firstWeekday`와 같은 값이다. 1 = 일요일, 2 = 월요일.
    @Published var firstWeekday: Int {
        didSet { defaults.set(firstWeekday, forKey: Key.firstWeekday) }
    }
    /// 달력과 목록, 메뉴바 어디에도 보이지 않는 캘린더.
    @Published var hiddenCalendarIDs: Set<String> {
        didSet { defaults.set(Array(hiddenCalendarIDs), forKey: Key.hiddenCalendarIDs) }
    }
    /// 달력과 목록에는 보이지만 메뉴바 제목으로는 쓰지 않는 캘린더.
    @Published var menuBarExcludedCalendarIDs: Set<String> {
        didSet { defaults.set(Array(menuBarExcludedCalendarIDs), forKey: Key.menuBarExcludedCalendarIDs) }
    }

    @Published var calendarAppTarget: CalendarAppTarget {
        didSet { defaults.set(calendarAppTarget.rawValue, forKey: Key.calendarAppTarget) }
    }
    /// `calendarAppTarget`이 `.custom`일 때 열 앱의 경로.
    @Published var customCalendarAppPath: String? {
        didSet { defaults.set(customCalendarAppPath, forKey: Key.customCalendarAppPath) }
    }

    private init() {
        defaults.register(defaults: [
            Key.showEventInMenuBar: true,
            Key.showLocationInMenuBar: false,
            Key.leadMinutes: 60,
            Key.maxTitleLength: 30,
            Key.daysToShow: 7,
            Key.firstWeekday: 1,
        ])
        showEventInMenuBar = defaults.bool(forKey: Key.showEventInMenuBar)
        showLocationInMenuBar = defaults.bool(forKey: Key.showLocationInMenuBar)
        leadMinutes = defaults.integer(forKey: Key.leadMinutes)
        maxTitleLength = defaults.integer(forKey: Key.maxTitleLength)
        daysToShow = defaults.integer(forKey: Key.daysToShow)
        firstWeekday = defaults.integer(forKey: Key.firstWeekday)
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: Key.hiddenCalendarIDs) ?? [])
        menuBarExcludedCalendarIDs = Set(defaults.stringArray(forKey: Key.menuBarExcludedCalendarIDs) ?? [])
        calendarAppTarget = defaults.string(forKey: Key.calendarAppTarget)
            .flatMap(CalendarAppTarget.init(rawValue:)) ?? .system
        customCalendarAppPath = defaults.string(forKey: Key.customCalendarAppPath)
    }
}
