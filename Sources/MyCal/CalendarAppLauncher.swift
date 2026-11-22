import AppKit

@MainActor
enum CalendarAppLauncher {
    private static let systemCalendarBundleID = "com.apple.iCal"

    /// 설정한 대상으로 캘린더를 연다. Google Calendar는 `date`가 속한 주 보기로 연다.
    /// 직접 고른 앱이 지워졌으면 macOS 캘린더를 연다.
    static func open(with settings: AppSettings, date: Date) {
        switch settings.calendarAppTarget {
        case .system:
            openSystemCalendar()
        case .google:
            NSWorkspace.shared.open(googleCalendarURL(for: date))
        case .custom:
            if let path = settings.customCalendarAppPath, FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
            } else {
                openSystemCalendar()
            }
        }
    }

    static func displayName(ofAppAt path: String) -> String {
        FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
    }

    private static func openSystemCalendar() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: systemCalendarBundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    nonisolated static func googleCalendarURL(for date: Date) -> URL {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return URL(string: "https://calendar.google.com/calendar/r/week/\(parts.year!)/\(parts.month!)/\(parts.day!)")!
    }
}
