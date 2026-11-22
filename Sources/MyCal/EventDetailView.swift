import AppKit
import EventKit
import SwiftUI

struct EventDetailView: View {
    let item: EventItem
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onClose) {
                Label("목록", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    DetailLine(icon: "clock", text: EventTimeText.make(for: item))
                    if let location = item.source.location, !location.isEmpty {
                        DetailLine(icon: "mappin.and.ellipse", text: location)
                    }
                    if let calendar = item.source.calendar {
                        DetailLine(icon: "calendar", text: calendar.title)
                    }
                    if let url = item.meetingURL {
                        Button { NSWorkspace.shared.open(url) } label: {
                            Label("화상회의 참여", systemImage: "video.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .help(url.absoluteString)
                    }
                    if let status = myStatus {
                        DetailLine(icon: "person.crop.circle", text: "내 응답: \(ParticipantStatusText.label(for: status))")
                    }
                    if let url = item.source.googleCalendarURL {
                        Button { NSWorkspace.shared.open(url) } label: {
                            Label(
                                myStatus == nil ? "Google Calendar에서 열기" : "Google Calendar에서 응답",
                                systemImage: "arrow.up.forward.app"
                            )
                        }
                        .buttonStyle(.bordered)
                        .help("참석 응답은 Google Calendar에서 바꿀 수 있습니다")
                    }
                    if !attendees.isEmpty {
                        AttendeeList(attendees: attendees, organizerURL: item.source.organizer?.url)
                    }
                    if let notes = item.source.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("메모").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                            Text(notes)
                                .font(.system(size: 13))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Color(nsColor: item.color)).frame(width: 10, height: 10)
            Text(item.title)
                .font(.system(size: 16, weight: .semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var myStatus: EKParticipantStatus? {
        item.source.attendees?.first(where: \.isCurrentUser)?.participantStatus
    }

    /// 회의실 같은 리소스는 이름이 비어 있어 사람 참석자만 보여준다.
    private var attendees: [EKParticipant] {
        (item.source.attendees ?? []).filter { $0.participantType == .person }
    }
}

private struct DetailLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AttendeeList: View {
    let attendees: [EKParticipant]
    let organizerURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(sorted, id: \.url) { attendee in
                HStack(spacing: 8) {
                    StatusIcon(status: attendee.participantStatus)
                    Text(displayName(attendee)).font(.system(size: 13)).lineLimit(1)
                    if attendee.url == organizerURL {
                        Text("주최자").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .help(attendee.url.absoluteString.replacingOccurrences(of: "mailto:", with: ""))
            }
        }
    }

    private var summary: String {
        let accepted = attendees.filter { $0.participantStatus == .accepted }.count
        let declined = attendees.filter { $0.participantStatus == .declined }.count
        return "참석자 \(attendees.count)명 · 수락 \(accepted) · 거절 \(declined)"
    }

    /// 주최자를 맨 위에 두고, 수락 → 미정 → 응답 대기 → 거절 순으로 정렬한다.
    private var sorted: [EKParticipant] {
        func rank(_ attendee: EKParticipant) -> Int {
            if attendee.url == organizerURL { return 0 }
            switch attendee.participantStatus {
            case .accepted: return 1
            case .tentative: return 2
            case .declined: return 4
            default: return 3
            }
        }
        return attendees.sorted {
            rank($0) != rank($1) ? rank($0) < rank($1) : displayName($0) < displayName($1)
        }
    }

    private func displayName(_ attendee: EKParticipant) -> String {
        if let name = attendee.name, !name.isEmpty { return name }
        return attendee.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
    }
}

private struct StatusIcon: View {
    let status: EKParticipantStatus

    var body: some View {
        let (symbol, color): (String, Color) = switch status {
        case .accepted: ("checkmark.circle.fill", .green)
        case .declined: ("xmark.circle.fill", .red)
        case .tentative: ("questionmark.circle.fill", .orange)
        default: ("circle", .secondary)
        }
        Image(systemName: symbol)
            .foregroundStyle(color)
            .help(ParticipantStatusText.label(for: status))
    }
}

enum ParticipantStatusText {
    static func label(for status: EKParticipantStatus) -> String {
        switch status {
        case .accepted: "수락"
        case .declined: "거절"
        case .tentative: "미정"
        case .pending: "응답 대기"
        case .delegated: "위임"
        default: "알 수 없음"
        }
    }
}

private enum EventTimeText {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func make(for item: EventItem) -> String {
        let calendar = Calendar.current
        let startDay = dayFormatter.string(from: item.start)
        if item.isAllDay {
            // 종일 일정의 endDate는 마지막 날 23:59:59이다.
            let endDay = dayFormatter.string(from: item.end)
            return startDay == endDay ? "\(startDay) 종일" : "\(startDay) ~ \(endDay)"
        }
        let start = timeFormatter.string(from: item.start)
        let end = timeFormatter.string(from: item.end)
        if calendar.isDate(item.start, inSameDayAs: item.end) {
            return "\(startDay) \(start) ~ \(end)"
        }
        return "\(startDay) \(start) ~ \(dayFormatter.string(from: item.end)) \(end)"
    }
}
