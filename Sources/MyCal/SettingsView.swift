import EventKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: CalendarStore
    // Command Line Tools에는 SwiftUI 매크로 플러그인이 없어 @State를 쓸 수 없다.
    @StateObject private var launchAtLogin = LaunchAtLogin()

    private static let leadOptions: [(minutes: Int, label: String)] = [
        (0, "진행 중일 때만"),
        (5, "5분 전"),
        (10, "10분 전"),
        (15, "15분 전"),
        (30, "30분 전"),
        (60, "1시간 전"),
        (120, "2시간 전"),
        (180, "3시간 전"),
        (360, "6시간 전"),
        (720, "12시간 전"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            form
            Divider()
            HStack {
                Spacer()
                Button("MyCal 종료") { NSApp.terminate(nil) }
            }
            .padding(12)
        }
        .frame(width: 480, height: 640)
    }

    private var form: some View {
        Form {
            Section("메뉴바") {
                Toggle("다가오는 일정과 진행 중인 일정 제목 표시", isOn: $settings.showEventInMenuBar)
                Toggle("회의실 위치 함께 표시", isOn: $settings.showLocationInMenuBar)
                    .disabled(!settings.showEventInMenuBar)
                Picker("표시 시작", selection: $settings.leadMinutes) {
                    ForEach(Self.leadOptions, id: \.minutes) { option in
                        Text(option.label).tag(option.minutes)
                    }
                }
                .disabled(!settings.showEventInMenuBar)
                Stepper("제목 최대 글자 수: \(settings.maxTitleLength)", value: $settings.maxTitleLength, in: 10...60, step: 5)
                    .disabled(!settings.showEventInMenuBar)
            }

            Section("달력") {
                Picker("한 주의 시작", selection: $settings.firstWeekday) {
                    Text("일요일").tag(1)
                    Text("월요일").tag(2)
                }
                Stepper("목록에 표시할 날짜 수: \(settings.daysToShow)일", value: $settings.daysToShow, in: 1...14)
            }

            Section {
                ForEach(groupedCalendars, id: \.source) { group in
                    Text(group.source).font(.caption).foregroundStyle(.secondary)
                    ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                        CalendarRow(calendar: calendar, settings: settings)
                    }
                }
            } header: {
                Text("캘린더")
            } footer: {
                Text("‘메뉴바’를 끄면 달력과 목록에는 보이지만 메뉴바 제목으로는 표시하지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("일반") {
                Picker("캘린더 버튼으로 열기", selection: Binding(
                    get: { settings.calendarAppTarget },
                    set: { target in
                        if target == .custom {
                            chooseCustomApp()
                        } else {
                            settings.calendarAppTarget = target
                        }
                    }
                )) {
                    Text("기본 캘린더 앱").tag(CalendarAppTarget.system)
                    Text("Google Calendar (웹)").tag(CalendarAppTarget.google)
                    Text(customAppLabel).tag(CalendarAppTarget.custom)
                }
                if settings.calendarAppTarget == .custom {
                    Button("다른 앱 선택…", action: chooseCustomApp)
                }
                Toggle("로그인 시 자동 실행", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                if let error = launchAtLogin.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var groupedCalendars: [(source: String, calendars: [EKCalendar])] {
        Dictionary(grouping: store.calendars) { $0.source.title }
            .map { (source: $0.key, calendars: $0.value) }
            .sorted { $0.source < $1.source }
    }

    private var customAppLabel: String {
        guard let path = settings.customCalendarAppPath else { return "다른 앱…" }
        return "다른 앱: \(CalendarAppLauncher.displayName(ofAppAt: path))"
    }

    /// 앱을 고르지 않고 취소하면 기존 선택을 유지한다.
    private func chooseCustomApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "선택"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.customCalendarAppPath = url.path
        settings.calendarAppTarget = .custom
    }
}

private struct CalendarRow: View {
    let calendar: EKCalendar
    @ObservedObject var settings: AppSettings

    var body: some View {
        let id = calendar.calendarIdentifier
        let visible = !settings.hiddenCalendarIDs.contains(id)

        HStack {
            Circle()
                .fill(Color(nsColor: NSColor(cgColor: calendar.cgColor) ?? .systemGray))
                .frame(width: 10, height: 10)
            Text(calendar.title)
            Spacer()
            Toggle("표시", isOn: Binding(
                get: { visible },
                set: { settings.hiddenCalendarIDs.toggle(id, included: !$0) }
            ))
            .toggleStyle(.checkbox)
            Toggle("메뉴바", isOn: Binding(
                get: { !settings.menuBarExcludedCalendarIDs.contains(id) },
                set: { settings.menuBarExcludedCalendarIDs.toggle(id, included: !$0) }
            ))
            .toggleStyle(.checkbox)
            .disabled(!visible)
        }
    }
}

@MainActor
private final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var errorMessage: String?

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}

private extension Set where Element == String {
    mutating func toggle(_ element: String, included: Bool) {
        if included { insert(element) } else { remove(element) }
    }
}
