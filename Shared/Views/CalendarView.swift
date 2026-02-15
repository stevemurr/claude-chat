import SwiftUI

struct CalendarView: View {
    @ObservedObject var dailyNoteService: DailyNoteService
    var onDateTap: (() -> Void)? = nil
    @State private var displayedMonth: Date = Date()

    private let calendar = Calendar.current
    private let weekdaySymbols = Calendar.current.veryShortWeekdaySymbols

    var body: some View {
        VStack(spacing: 8) {
            // Month/Year Header with Navigation
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthYearString)
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            // Weekday Headers
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Calendar Grid
            let days = daysInMonth
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(days, id: \.self) { date in
                    if let date = date {
                        DayCell(
                            date: date,
                            isSelected: isSameDay(date, dailyNoteService.selectedDate),
                            isToday: isSameDay(date, Date()),
                            hasContent: dailyNoteService.hasContent(for: date)
                        ) {
                            dailyNoteService.selectDate(date)
                            onDateTap?()
                        }
                    } else {
                        Color.clear
                            .frame(height: 28)
                    }
                }
            }

            Divider()
                .padding(.vertical, 8)

            WeekView(dailyNoteService: dailyNoteService, onDateTap: onDateTap)
        }
        .padding(12)
    }

    // MARK: - Computed Properties

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }

        var days: [Date?] = []

        // Calculate the first day to show (start of the week containing the 1st)
        var currentDate = monthFirstWeek.start

        // Get the last day of the month
        let monthEnd = calendar.date(byAdding: .day, value: -1, to: monthInterval.end)!

        // Fill in all days from start of first week to end of month
        while currentDate <= monthEnd || days.count % 7 != 0 {
            let isInMonth = calendar.isDate(currentDate, equalTo: displayedMonth, toGranularity: .month)
            days.append(isInMonth ? currentDate : nil)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!

            // Safety limit
            if days.count > 42 { break }
        }

        return days
    }

    // MARK: - Actions

    private func previousMonth() {
        if let newDate = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
            displayedMonth = newDate
        }
    }

    private func nextMonth() {
        if let newDate = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
            displayedMonth = newDate
        }
    }

    private func isSameDay(_ date1: Date, _ date2: Date) -> Bool {
        calendar.isDate(date1, inSameDayAs: date2)
    }
}

// MARK: - Day Cell

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasContent: Bool
    let onTap: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular))
                    .foregroundColor(textColor)

                // Content indicator dot
                Circle()
                    .fill(hasContent ? Color.accentColor : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(width: 28, height: 28)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isToday && !isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var textColor: Color {
        if isSelected {
            return .white
        }
        return .primary
    }

    private var backgroundColor: Color {
        if isSelected {
            return .accentColor
        }
        return .clear
    }
}

// Preview requires ModelContainer - use Xcode canvas instead
