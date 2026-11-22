import AppKit
import Combine
import EventKit
import MyCalCore
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    /// 지금 항목에 지정한 너비. 이 값이 바뀌면 항목을 새로 만든다.
    private var appliedLength: CGFloat?
    private let popover = NSPopover()
    private let store: CalendarStore
    private let settings: AppSettings
    private let viewModel: CalendarViewModel
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(store: CalendarStore, settings: AppSettings, openSettings: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self.viewModel = CalendarViewModel(store: store, settings: settings)
        super.init()

        popover.behavior = .transient
        // 콘텐츠를 흰 배경으로 그리므로 다크 모드에서도 밝은 모양을 쓴다. 그래야 글자색과 팝오버 화살표가 배경과 맞는다.
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(model: viewModel, store: store, openSettings: openSettings)
        )

        configure(statusItem)

        // objectWillChange는 값이 바뀌기 직전에 오므로 다음 런루프에서 읽는다.
        settings.objectWillChange
            .merge(with: store.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        // NSCalendarDayChanged 같은 시간 알림은 백그라운드 스레드에서 오므로 메인 큐로 옮겨 받는다.
        // 다른 스레드에서 메뉴바 버튼을 건드리면 AppKit이 예외를 던져 앱이 종료된다.
        let center = NotificationCenter.default
        Publishers.MergeMany(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification),
            center.publisher(for: .NSCalendarDayChanged),
            center.publisher(for: .NSSystemClockDidChange),
            center.publisher(for: .NSSystemTimeZoneDidChange)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.clockChanged() }
        .store(in: &cancellables)

        scheduleTimer()
        refresh()
    }

    func closePopover() {
        popover.performClose(nil)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        viewModel.showToday()
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func clockChanged() {
        scheduleTimer()
        refresh()
        viewModel.reload()
    }

    /// 일정은 보통 분 단위로 시작하고 끝나므로 매 분 정각 직후에 갱신한다.
    private func scheduleTimer() {
        timer?.invalidate()
        let now = Date()
        let nextMinute = Calendar.current.nextDate(
            after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(60)
        let timer = Timer(fire: nextMinute.addingTimeInterval(0.2), interval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func configure(_ item: NSStatusItem) {
        // 다시 만든 항목이 사용자가 옮겨 둔 메뉴바 위치로 돌아가도록 같은 이름으로 위치를 저장한다.
        item.autosaveName = "MyCalStatusItem"
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        // 시스템이 정한 칸보다 글자가 길어도 옆 항목 위로 넘쳐 그리지 않고 말줄임표로 자른다.
        button.lineBreakMode = .byTruncatingTail
    }

    private func refresh() {
        let content = makeContent(now: Date())
        apply(content, to: statusItem)
        guard let button = statusItem.button else { return }
        let length = min(ceil(button.fittingSize.width / Self.lengthStep) * Self.lengthStep, Self.maxTitleWidth)

        // 모니터가 여러 대이면 macOS가 다른 모니터 메뉴바에 그리는 항목 복사본이 처음 만들어질 때의
        // 너비를 계속 쓴다. 너비를 바꿔도 반영되지 않아 옆 항목과 겹치므로, 너비가 바뀌면 항목을 새로 만든다.
        // 팝오버가 열려 있으면 기준 버튼이 사라지지 않도록 다음 갱신으로 미룬다.
        if let appliedLength, appliedLength != length {
            guard !popover.isShown else { return }
            NSStatusBar.system.removeStatusItem(statusItem)
            statusItem = NSStatusBar.system.statusItem(withLength: length)
            configure(statusItem)
            apply(content, to: statusItem)
        }
        statusItem.length = length
        appliedLength = length
    }

    private struct Content {
        let image: NSImage
        let imagePosition: NSControl.ImagePosition
        let title: String
        let toolTip: String?
    }

    private func makeContent(now: Date) -> Content {
        guard settings.showEventInMenuBar, let (status, event) = currentStatus(now: now) else {
            return Content(
                image: StatusIcons.calendar(day: Calendar.current.component(.day, from: now)),
                imagePosition: .imageOnly,
                title: "",
                toolTip: nil
            )
        }
        let text = MenuBarText.text(
            for: status,
            maxTitleLength: settings.maxTitleLength,
            includeLocation: settings.showLocationInMenuBar
        )
        return Content(
            image: StatusIcons.dot(color: event.displayColor, filled: !event.isPending),
            imagePosition: .imageLeading,
            title: " " + text,
            toolTip: [status.event.title, status.event.location].compactMap { $0 }.joined(separator: "\n")
        )
    }

    private func apply(_ content: Content, to item: NSStatusItem) {
        guard let button = item.button else { return }
        button.image = content.image
        button.imagePosition = content.imagePosition
        button.title = content.title
        button.toolTip = content.toolTip
    }

    /// 분이 바뀌며 글자 폭이 조금씩 달라질 때마다 항목을 다시 만들지 않도록 너비를 이 단위로 올림한다.
    private static let lengthStep: CGFloat = 16

    /// 일정 제목이 메뉴바를 지나치게 차지하지 않도록 둔 상한. 넘치면 말줄임표로 자른다.
    private static let maxTitleWidth: CGFloat = 360

    private func currentStatus(now: Date) -> (MenuBarStatus, EKEvent)? {
        let leadTime = TimeInterval(settings.leadMinutes * 60)
        let excluded = settings.hiddenCalendarIDs.union(settings.menuBarExcludedCalendarIDs)
        // 하루 넘게 이어지는 일정도 진행 중으로 잡기 위해 하루 전부터 읽는다.
        let events = store.events(
            from: now.addingTimeInterval(-86_400),
            to: now.addingTimeInterval(leadTime + 60),
            excluding: excluded
        )
        guard let status = MenuBarStatusResolver.resolve(events: events.map(\.snapshot), now: now, leadTime: leadTime),
              let event = events.first(where: { $0.occurrenceID == status.event.id })
        else {
            return nil
        }
        return (status, event)
    }
}

enum StatusIcons {
    /// 목록과 같이 응답 대기 중인 일정은 속이 빈 원으로 그린다.
    static func dot(color: NSColor, filled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            if filled {
                color.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            } else {
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1.25, dy: 1.25))
                ring.lineWidth = 1.5
                color.setStroke()
                ring.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    static func calendar(day: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            let body = NSRect(x: 1.5, y: 1, width: 17, height: 14)
            let outline = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3)
            NSColor.black.set()
            outline.lineWidth = 1.2
            outline.stroke()

            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            NSRect(x: body.minX, y: body.maxY - 3.5, width: body.width, height: 3.5).fill()
            NSGraphicsContext.restoreGraphicsState()

            // 줄 높이에는 숫자에 없는 디센더 공간이 포함되어 숫자가 아래로 쏠린다.
            // 그래서 실제 글리프 외곽을 기준으로 가운데에 놓는다.
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: "\(day)",
                attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .bold)]
            ))
            let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let inset = outline.lineWidth / 2
            let numberArea = NSRect(
                x: body.minX + inset,
                y: body.minY + inset,
                width: body.width - inset * 2,
                height: body.height - 3.5 - inset
            )
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.textPosition = CGPoint(
                x: numberArea.midX - glyphs.width / 2 - glyphs.minX,
                y: numberArea.midY - glyphs.height / 2 - glyphs.minY
            )
            CTLineDraw(line, context)
            return true
        }
        image.isTemplate = true
        return image
    }
}
