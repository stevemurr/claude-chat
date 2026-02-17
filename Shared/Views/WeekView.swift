import SwiftUI
#if os(iOS)
import UIKit
#endif

struct WeekView: View {
    @ObservedObject var dailyNoteService: DailyNoteService
    var onDateTap: (() -> Void)? = nil

    var body: some View {
        #if os(macOS)
        WeekViewMac(dailyNoteService: dailyNoteService, onDateTap: onDateTap)
        #else
        WeekViewiOS(dailyNoteService: dailyNoteService, onDateTap: onDateTap)
        #endif
    }
}

// MARK: - iOS Version (Infinite scroll with UIKit for proper gesture handling)

#if os(iOS)
/// Custom UIScrollView that only handles vertical gestures and lets horizontal pass to TabView
class VerticalOnlyScrollView: UIScrollView {
    private var initialTouchPoint: CGPoint = .zero
    private var directionDetermined = false
    private var isVerticalScroll = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        directionDetermined = false
        isVerticalScroll = false
        if let touch = touches.first {
            initialTouchPoint = touch.location(in: self)
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !directionDetermined, let touch = touches.first {
            let currentPoint = touch.location(in: self)
            let dx = abs(currentPoint.x - initialTouchPoint.x)
            let dy = abs(currentPoint.y - initialTouchPoint.y)

            // Need at least 10 points of movement to determine direction
            if dx > 10 || dy > 10 {
                directionDetermined = true
                isVerticalScroll = dy > dx

                if !isVerticalScroll {
                    // Horizontal gesture - cancel our touches and let TabView handle it
                    panGestureRecognizer.isEnabled = false
                    panGestureRecognizer.isEnabled = true
                    return
                }
            }
        }
        super.touchesMoved(touches, with: event)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == panGestureRecognizer {
            let velocity = panGestureRecognizer.velocity(in: self)
            // Only begin if primarily vertical (with some tolerance)
            return abs(velocity.y) >= abs(velocity.x)
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

/// UIScrollView wrapper that allows horizontal gestures to pass through to parent (TabView)
struct VerticalScrollView<Content: View>: UIViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIView(context: Context) -> VerticalOnlyScrollView {
        let scrollView = VerticalOnlyScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = false
        scrollView.isDirectionalLockEnabled = true
        scrollView.contentInsetAdjustmentBehavior = .never

        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.clipsToBounds = true

        scrollView.addSubview(hostingController.view)
        context.coordinator.hostingController = hostingController

        // Lock content width to scroll view width to prevent horizontal scrolling
        let widthConstraint = hostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        widthConstraint.priority = .required

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            widthConstraint
        ])

        return scrollView
    }

    func updateUIView(_ scrollView: VerticalOnlyScrollView, context: Context) {
        context.coordinator.hostingController?.rootView = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>?

        // Prevent horizontal scrolling by resetting x offset
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if scrollView.contentOffset.x != 0 {
                scrollView.contentOffset.x = 0
            }
        }
    }
}
#endif

struct DaysListContent: View {
    @ObservedObject var dailyNoteService: DailyNoteService
    let dayRange: ClosedRange<Int>
    let startOfToday: Date
    var onDateTap: (() -> Void)?
    let loadMoreIfNeeded: (Int) -> Void

    private let calendar = Calendar.current

    var body: some View {
        LazyVStack(spacing: 2) {
            ForEach(dayRange.map { $0 }, id: \.self) { offset in
                let date = calendar.date(byAdding: .day, value: offset, to: startOfToday) ?? Date()
                let prevDate = calendar.date(byAdding: .day, value: offset - 1, to: startOfToday) ?? Date()

                // Show month header when month changes
                if !calendar.isDate(date, equalTo: prevDate, toGranularity: .month) || offset == dayRange.lowerBound {
                    MonthHeader(date: date)
                        .padding(.top, offset == dayRange.lowerBound ? 0 : 12)
                        .padding(.bottom, 4)
                }

                WeekDayRow(
                    date: date,
                    note: dailyNoteService.note(for: date),
                    isToday: offset == 0,
                    isSelected: calendar.isDate(date, inSameDayAs: dailyNoteService.selectedDate)
                ) {
                    dailyNoteService.selectDate(date)
                    onDateTap?()
                }
                .onAppear {
                    loadMoreIfNeeded(offset)
                }
            }
        }
        .padding(.bottom, 20)
    }
}

#if os(iOS)
struct WeekViewiOS: View {
    @ObservedObject var dailyNoteService: DailyNoteService
    var onDateTap: (() -> Void)? = nil

    @State private var dayRange: ClosedRange<Int> = -14...14

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with today button
            HStack {
                Text("Days")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: scrollToToday) {
                    Text("Today")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 4)

            VerticalScrollView {
                DaysListContent(
                    dailyNoteService: dailyNoteService,
                    dayRange: dayRange,
                    startOfToday: startOfToday,
                    onDateTap: onDateTap,
                    loadMoreIfNeeded: loadMoreIfNeeded
                )
            }
        }
    }

    private var startOfToday: Date {
        calendar.startOfDay(for: Date())
    }

    private func scrollToToday() {
        dailyNoteService.selectDate(Date())
    }

    private func loadMoreIfNeeded(offset: Int) {
        // Load more past days (threshold of 3 items)
        if offset <= dayRange.lowerBound + 3 {
            let newLower = dayRange.lowerBound - 14
            dayRange = newLower...dayRange.upperBound
        }
        // Load more future days (threshold of 3 items)
        if offset >= dayRange.upperBound - 3 {
            let newUpper = dayRange.upperBound + 14
            dayRange = dayRange.lowerBound...newUpper
        }
    }
}
#endif

// MARK: - macOS Version (Infinite scroll)

struct WeekViewMac: View {
    @ObservedObject var dailyNoteService: DailyNoteService
    var onDateTap: (() -> Void)? = nil

    @State private var dayRange: ClosedRange<Int> = -30...30
    @State private var hasScrolledToToday = false
    @State private var isReady = false

    private let calendar = Calendar.current

    private var dayOffsets: [Int] {
        Array(dayRange)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with today button
            HStack {
                Text("Days")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: scrollToToday) {
                    Text("Today")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            if isReady {
                scrollContent
            } else {
                // Placeholder during initial layout
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        DispatchQueue.main.async {
                            isReady = true
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(dayOffsets, id: \.self) { offset in
                            let date = calendar.date(byAdding: .day, value: offset, to: startOfToday) ?? Date()
                            let prevDate = calendar.date(byAdding: .day, value: offset - 1, to: startOfToday) ?? Date()

                            // Show month header when month changes
                            if !calendar.isDate(date, equalTo: prevDate, toGranularity: .month) || offset == dayRange.lowerBound {
                                MonthHeader(date: date)
                                    .padding(.top, offset == dayRange.lowerBound ? 0 : 12)
                                    .padding(.bottom, 4)
                            }

                            WeekDayRow(
                                date: date,
                                note: dailyNoteService.note(for: date),
                                isToday: offset == 0,
                                isSelected: calendar.isDate(date, inSameDayAs: dailyNoteService.selectedDate)
                            ) {
                                dailyNoteService.selectDate(date)
                                onDateTap?()
                            }
                            .id(offset)
                            .onAppear {
                                loadMoreIfNeeded(offset: offset)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.never)
                .onAppear {
                    if !hasScrolledToToday {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo(0, anchor: .top)
                            hasScrolledToToday = true
                        }
                    }
                }
            .onChange(of: dailyNoteService.selectedDate) { _, newDate in
                let offset = calendar.dateComponents([.day], from: startOfToday, to: newDate).day ?? 0
                withAnimation {
                    proxy.scrollTo(offset, anchor: .center)
                }
            }
        }
    }

    private var startOfToday: Date {
        calendar.startOfDay(for: Date())
    }

    private func scrollToToday() {
        dailyNoteService.selectDate(Date())
    }

    private func loadMoreIfNeeded(offset: Int) {
        // Load more past days
        if offset == dayRange.lowerBound + 5 {
            let newLower = dayRange.lowerBound - 30
            dayRange = newLower...dayRange.upperBound
        }
        // Load more future days
        if offset == dayRange.upperBound - 5 {
            let newUpper = dayRange.upperBound + 30
            dayRange = dayRange.lowerBound...newUpper
        }
    }
}

// MARK: - Week Day Row

struct WeekDayRow: View {
    let date: Date
    let note: DailyNote?
    let isToday: Bool
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovering = false
    private let calendar = Calendar.current

    private var stats: NoteContentStats {
        guard let note = note else { return .empty }
        return NoteContentParser.parse(note.content)
    }

    private var hasContent: Bool {
        note?.hasContent ?? false
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Date column - fixed width for alignment
                VStack(alignment: .center, spacing: 0) {
                    Text(dayAbbrev)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isToday ? .accentColor : .secondary.opacity(0.7))
                        .textCase(.uppercase)

                    Text(dayNumber)
                        .font(.system(size: 15, weight: isToday ? .semibold : .regular, design: .rounded))
                        .foregroundColor(isToday ? .accentColor : .primary)
                }
                .frame(width: 32)

                // Content column
                VStack(alignment: .leading, spacing: 2) {
                    if hasContent {
                        // Show first bullet or a preview
                        if let firstBullet = stats.bulletItems.first {
                            Text(firstBullet)
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }

                        // Secondary info row
                        HStack(spacing: 6) {
                            if let badge = stats.todoBadge {
                                Label(badge, systemImage: todoBadgeIcon)
                                    .font(.system(size: 10))
                                    .foregroundColor(todoBadgeColor)
                            }

                            if stats.bulletItems.count > 1 {
                                Text("+\(stats.bulletItems.count - 1) more")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("No notes")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)

                // Today indicator
                if isToday {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { hovering in
            isHovering = hovering
        }
        #endif
    }

    private var dayAbbrev: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private var todoBadgeIcon: String {
        if stats.allTodosComplete {
            return "checkmark.circle.fill"
        } else if stats.partialTodosComplete {
            return "circle.lefthalf.filled"
        }
        return "circle"
    }

    private var todoBadgeColor: Color {
        if stats.allTodosComplete {
            return .green
        } else if stats.partialTodosComplete {
            return .orange
        }
        return .secondary
    }

    private var rowBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.15))
        } else if isHovering {
            return AnyShapeStyle(Color.primary.opacity(0.05))
        }
        return AnyShapeStyle(Color.clear)
    }
}

// MARK: - Month Header

struct MonthHeader: View {
    let date: Date

    private var monthString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        HStack {
            Text(monthString)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

#if DEBUG
struct WeekView_Previews: PreviewProvider {
    static var previews: some View {
        WeekView(dailyNoteService: DailyNoteService())
            .padding()
            .frame(width: 280, height: 400)
    }
}
#endif
