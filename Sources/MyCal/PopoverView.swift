import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: CalendarViewModel
    @ObservedObject var store: CalendarStore
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if store.hasAccess {
                MonthView(model: model)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                ToolbarRow(model: model, openSettings: openSettings)
                Divider()
                if let detail = model.detailEvent {
                    EventDetailView(item: detail, onClose: model.closeDetail)
                } else {
                    EventListView(model: model)
                }
            } else {
                AccessRequiredView(openSettings: openSettings)
            }
        }
        .frame(width: 300, height: 760)
        .background(Color.white)
    }
}

private struct MonthView: View {
    @ObservedObject var model: CalendarViewModel

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 yyyy"
        return formatter
    }()

    var body: some View {
        let calendar = model.calendar
        VStack(spacing: 6) {
            HStack {
                Text(Self.titleFormatter.string(from: model.displayedMonth))
                    .font(.title2.weight(.bold))
                Spacer()
                HStack(spacing: 2) {
                    Button { model.moveMonth(by: -1) } label: {
                        Image(systemName: "chevron.left").modifier(HoverHighlight())
                    }
                    .help("이전 달")
                    Button { model.showToday() } label: {
                        Image(systemName: "circle.fill").font(.system(size: 7)).modifier(HoverHighlight())
                    }
                    .help("오늘로 이동")
                    Button { model.moveMonth(by: 1) } label: {
                        Image(systemName: "chevron.right").modifier(HoverHighlight())
                    }
                    .help("다음 달")
                }
            }
            .buttonStyle(.borderless)

            HStack(spacing: 3) {
                ForEach(model.weekdayHeaders, id: \.weekday) { header in
                    Text(header.symbol)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(weekendColor(header.weekday) ?? .secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            let days = model.gridDays
            VStack(spacing: 3) {
                ForEach(0..<6, id: \.self) { week in
                    HStack(spacing: 3) {
                        ForEach(days[(week * 7)..<(week * 7 + 7)], id: \.self) { day in
                            DayCell(
                                day: calendar.component(.day, from: day),
                                weekday: calendar.component(.weekday, from: day),
                                inMonth: calendar.isDate(day, equalTo: model.displayedMonth, toGranularity: .month),
                                isToday: calendar.isDateInToday(day),
                                isSelected: calendar.isDate(day, inSameDayAs: model.selectedDate),
                                highlight: model.hoveredDays.contains(day) ? model.hoveredEvent?.color : nil,
                                markers: model.dayMarkers[day] ?? []
                            )
                            .onTapGesture { model.select(day) }
                        }
                    }
                }
            }
        }
    }
}

// Command Line Tools에는 SwiftUI 매크로 플러그인이 없어 @State 대신 ObservableObject로 호버 상태를 둔다.
private final class HoverState: ObservableObject {
    @Published var isHovering = false
}

/// 마우스를 올리면 버튼 뒤에 옅은 배경을 깐다.
private struct HoverHighlight: ViewModifier {
    @StateObject private var hover = HoverState()

    func body(content: Content) -> some View {
        content
            .frame(width: 22, height: 22)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(hover.isHovering ? 0.1 : 0))
            }
            .contentShape(Rectangle())
            .onHover { hover.isHovering = $0 }
    }
}

/// 한국 달력 관례대로 일요일은 빨강, 토요일은 파랑. 평일이면 nil.
private func weekendColor(_ weekday: Int) -> Color? {
    switch weekday {
    case 1: Color(nsColor: .systemRed)
    case 7: Color(nsColor: .systemBlue)
    default: nil
    }
}

private struct DayCell: View {
    let day: Int
    let weekday: Int
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    /// 목록에서 마우스를 올린 일정이 이 날짜에 걸쳐 있으면 그 일정의 색.
    let highlight: NSColor?
    let markers: [NSColor]

    var body: some View {
        VStack(spacing: 2) {
            Text("\(day)")
                .font(.system(size: 14, weight: isToday ? .bold : .medium))
                .foregroundStyle((weekendColor(weekday) ?? .primary).opacity(inMonth ? 1 : 0.3))
            HStack(spacing: 2) {
                ForEach(Array(markers.enumerated()), id: \.offset) { _, color in
                    Circle().fill(Color(nsColor: color)).frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
            .opacity(inMonth ? 1 : 0.4)
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .background {
            RoundedRectangle(cornerRadius: 6).fill(tileFill)
        }
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
    }

    /// 이번 달 날짜에만 타일을 깔고, 다른 달 날짜는 배경 없이 둔다.
    private var tileFill: Color {
        if let highlight { return Color(nsColor: highlight).opacity(0.35) }
        if isSelected && !isToday { return Color.accentColor.opacity(0.22) }
        return inMonth ? Color.primary.opacity(0.07) : .clear
    }
}

private struct ToolbarRow: View {
    @ObservedObject var model: CalendarViewModel
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Spacer()
            Button { model.openCalendarApp() } label: { Image(systemName: "calendar") }
                .help("캘린더 열기")
            Button(action: openSettings) { Image(systemName: "gearshape") }
                .help("설정")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 15))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct EventListView: View {
    @ObservedObject var model: CalendarViewModel

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.sections.isEmpty {
                    Text("일정 없음")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
                ForEach(model.sections) { section in
                    // 여러 날에 걸친 일정은 날마다 같은 id로 다시 나온다. 섹션을 하나의 VStack으로 묶어
                    // 일정 id가 섹션 안에서만 구분되게 한다.
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(label(for: section.day)).font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text(Self.dateFormatter.string(from: section.day))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                        ForEach(section.events) { event in
                            EventRow(event: event, isHovered: model.hoveredEvent?.id == event.id)
                                .onHover { model.setHovering($0, over: event) }
                                .onTapGesture { model.showDetail(event) }
                        }
                        Divider().padding(.top, 6)
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func label(for day: Date) -> String {
        let calendar = model.calendar
        if calendar.isDateInToday(day) { return "오늘" }
        if calendar.isDateInTomorrow(day) { return "내일" }
        return Self.weekdayFormatter.string(from: day)
    }
}

private struct EventRow: View {
    let event: EventItem
    let isHovered: Bool

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        let color = Color(nsColor: event.color)
        let finished = event.end <= Date()

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if event.isAllDay {
                Capsule().fill(color).frame(width: 6, height: 15)
            } else if event.isPending {
                Circle().strokeBorder(color, lineWidth: 1.5).frame(width: 9, height: 9)
            } else {
                Circle().fill(color).frame(width: 9, height: 9)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 14.5, weight: .medium))
                    .strikethrough(event.isDeclined)
                    .lineLimit(1)
                if !event.isAllDay {
                    if let location = event.location {
                        Text(location).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text("\(Self.timeFormatter.string(from: event.start)) ~ \(Self.timeFormatter.string(from: event.end))")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        if let url = event.meetingURL {
                            Button { NSWorkspace.shared.open(url) } label: {
                                Image(systemName: "video").foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.borderless)
                            .help(url.absoluteString)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(finished || event.isDeclined ? 0.5 : 1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06))
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
    }
}

private struct AccessRequiredView: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 36))
            Text("캘린더 접근 권한이 필요합니다").font(.headline)
            Text("시스템 설정 → 개인정보 보호 및 보안 → 캘린더에서\nMyCal에 전체 접근을 허용하세요.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("시스템 설정 열기") {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
                NSWorkspace.shared.open(url)
            }
            Spacer()
            Button("MyCal 종료") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .padding(.bottom, 12)
        }
        .padding()
    }
}
