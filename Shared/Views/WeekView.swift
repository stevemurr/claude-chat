import SwiftUI

struct WeekView: View {
    @ObservedObject var dailyNoteService: DailyNoteService
    var onDateTap: (() -> Void)? = nil

    private let calendar: Calendar = {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        return cal
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This Week")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { date in
                    WeekDayCard(
                        date: date,
                        note: dailyNoteService.note(for: date),
                        isToday: calendar.isDateInToday(date),
                        isSelected: calendar.isDate(date, inSameDayAs: dailyNoteService.selectedDate)
                    ) {
                        dailyNoteService.selectDate(date)
                        onDateTap?()
                    }

                    if date != weekDays.last {
                        Divider()
                            .padding(.leading, 8)
                    }
                }
            }
            .background(Color.platformControlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.platformSeparator, lineWidth: 0.5)
            )
        }
    }

    /// Get the 7 days of the current week (Mon-Sun)
    private var weekDays: [Date] {
        let today = Date()
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return []
        }

        var days: [Date] = []
        var currentDate = weekInterval.start

        for _ in 0..<7 {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        return days
    }
}

// MARK: - Week Day Card

struct WeekDayCard: View {
    let date: Date
    let note: DailyNote?
    let isToday: Bool
    let isSelected: Bool
    let onTap: () -> Void

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
            VStack(alignment: .leading, spacing: 6) {
                // Header row: Day name, date, and todo badge
                HStack {
                    Text(dayString)
                        .font(.system(size: 12, weight: isToday ? .bold : .medium))
                        .foregroundColor(isToday ? .accentColor : .primary)

                    if isToday {
                        Text("TODAY")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    Spacer()

                    if let badge = stats.todoBadge {
                        Text(badge)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(todoBadgeColor)
                    }
                }

                // Content preview (only if there's content)
                if hasContent && !stats.bulletItems.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(stats.bulletItems.prefix(2), id: \.self) { item in
                            HStack(spacing: 4) {
                                Text("•")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text(item)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.leading, 2)

                    // Footer with link/video counts
                    if let footer = stats.footerText {
                        Text(footer)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 2)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d"
        return formatter.string(from: date)
    }

    private var todoBadgeColor: Color {
        if stats.allTodosComplete {
            return .green
        } else if stats.partialTodosComplete {
            return .orange
        }
        return .secondary
    }

    private var cardBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.1)
        }
        return Color.clear
    }
}

#if DEBUG
struct WeekView_Previews: PreviewProvider {
    static var previews: some View {
        WeekView(dailyNoteService: DailyNoteService())
            .padding()
            .frame(width: 280)
    }
}
#endif
