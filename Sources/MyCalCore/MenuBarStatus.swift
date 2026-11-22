import Foundation

public struct EventSnapshot: Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let isDeclined: Bool
    public let location: String?
    /// 일정에 Google Workspace 회의실 리소스가 예약되어 있으면 true. 이때 `location`은
    /// Google이 만든 회의실 이름("건물-층-구역-이름 (수용 인원) [기능]")을 쉼표로 이은 값이다.
    public let hasGoogleRoom: Bool

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        isDeclined: Bool,
        location: String? = nil,
        hasGoogleRoom: Bool = false
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isDeclined = isDeclined
        self.location = location
        self.hasGoogleRoom = hasGoogleRoom
    }
}

public enum MenuBarPhase: Equatable, Sendable {
    case ongoing(remaining: TimeInterval)
    case upcoming(startsIn: TimeInterval)
}

public struct MenuBarStatus: Equatable, Sendable {
    public let event: EventSnapshot
    public let phase: MenuBarPhase
}

public enum MenuBarStatusResolver {
    /// 진행 중인 일정이 있으면 그 일정을, 없으면 `leadTime` 안에 시작하는 가장 가까운 일정을 고른다.
    /// 종일 일정과 거절한 일정은 메뉴바에 표시하지 않는다.
    public static func resolve(events: [EventSnapshot], now: Date, leadTime: TimeInterval) -> MenuBarStatus? {
        let candidates = events.lazy.filter { !$0.isAllDay && !$0.isDeclined && $0.end > $0.start }

        // 진행 중인 일정이 겹치면 가장 늦게 시작한 일정을, 시작 시각이 같으면 먼저 끝나는 일정을 고른다.
        let current = candidates.filter { $0.start <= now && now < $0.end }.max { lhs, rhs in
            lhs.start != rhs.start ? lhs.start < rhs.start : lhs.end > rhs.end
        }
        if let current {
            return MenuBarStatus(event: current, phase: .ongoing(remaining: current.end.timeIntervalSince(now)))
        }

        let next = candidates
            .filter { $0.start > now && $0.start.timeIntervalSince(now) <= leadTime }
            .min { $0.start < $1.start }
        if let next {
            return MenuBarStatus(event: next, phase: .upcoming(startsIn: next.start.timeIntervalSince(now)))
        }
        return nil
    }
}

public enum MenuBarText {
    public static func text(for status: MenuBarStatus, maxTitleLength: Int, includeLocation: Bool = false) -> String {
        var parts = [truncate(status.event.title, to: maxTitleLength)]
        if includeLocation, let place = shortLocation(status.event.location, hasGoogleRoom: status.event.hasGoogleRoom) {
            parts.append(place)
        }
        switch status.phase {
        case .ongoing(let remaining):
            parts.append("\(duration(remaining)) 남음")
        case .upcoming(let startsIn):
            parts.append("\(duration(startsIn)) 후")
        }
        return parts.joined(separator: " · ")
    }

    /// 메뉴바에 넣을 위치. Google 회의실이 예약된 일정은 첫 회의실 이름만 남기고
    /// 나머지 회의실은 개수로 줄인다. 그 밖의 위치는 해석하지 않고 그대로 쓴다.
    public static func shortLocation(_ location: String?, hasGoogleRoom: Bool) -> String? {
        guard let location else { return nil }
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("://") else { return nil }
        guard hasGoogleRoom else { return truncate(trimmed, to: 20) }

        let rooms = trimmed
            .components(separatedBy: ", ")
            .map(googleRoomName)
            .filter { !$0.isEmpty }
        guard let first = rooms.first else { return truncate(trimmed, to: 20) }
        let name = truncate(first, to: 20)
        return rooms.count > 1 ? "\(name) 외 \(rooms.count - 1)" : name
    }

    /// "건물-층-구역-이름 (수용 인원) [기능]"에서 이름만 꺼낸다.
    private static func googleRoomName(_ resource: String) -> String {
        var name = resource.components(separatedBy: "-").last ?? resource
        name = name.replacingOccurrences(of: #"\s*\[[^\]]*\]\s*$"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"\s*\(\d+\)\s*$"#, with: "", options: .regularExpression)
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 분 단위로 올림한다. 59초가 남았을 때 "0분"이 아니라 "1분"으로 보여야 한다.
    public static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes)분" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)시간" : "\(hours)시간 \(rest)분"
    }

    public static func truncate(_ title: String, to maxLength: Int) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "(제목 없음)" }
        guard maxLength > 0, trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)) + "…"
    }
}
