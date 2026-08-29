import Foundation

struct CalendarOccurrence: Identifiable, Hashable {
    let id: String
    let course: ClassCourse
    let date: Date
    let originalDate: Date
    let startMinutes: Int
    let endMinutes: Int
    let session: ClassSession?

    var displayName: String {
        session?.classNameSnapshot ?? "\(course.name) Class \(weekday.name)"
    }
    var weekday: Weekday {
        Weekday(rawValue: Calendar.current.component(.weekday, from: date)) ?? course.weekday
    }
    var location: String { session?.locationSnapshot ?? course.location }
    var notes: String { session?.notesSnapshot ?? course.notes ?? "" }
    var recurrence: String { session?.recurrenceSnapshot ?? course.recurrence }
    var isMakeupClass: Bool { session?.isMakeupClassSnapshot ?? course.isMakeupClass }
    var timeLabel: String {
        ClassCourse(name: "", weekday: weekday, startMinutes: startMinutes, endMinutes: endMinutes, location: "", color: .blue).timeLabel
    }
}

struct CalendarOccurrencePlacement: Identifiable {
    let occurrence: CalendarOccurrence
    let lane: Int
    let laneCount: Int
    var id: String { occurrence.id }
}

enum CalendarLogic {
    static func placements(for occurrences: [CalendarOccurrence], calendar: Calendar = .current) -> [CalendarOccurrencePlacement] {
        let grouped = Dictionary(grouping: occurrences) { calendar.startOfDay(for: $0.date) }
        return grouped.values.flatMap { dayOccurrences in
            let sorted = dayOccurrences.sorted { $0.startMinutes == $1.startMinutes ? $0.endMinutes < $1.endMinutes : $0.startMinutes < $1.startMinutes }
            var groups: [[CalendarOccurrence]] = []
            var current: [CalendarOccurrence] = []
            var groupEnd = -1
            for occurrence in sorted {
                if !current.isEmpty && occurrence.startMinutes >= groupEnd {
                    groups.append(current); current = []; groupEnd = -1
                }
                current.append(occurrence)
                groupEnd = max(groupEnd, occurrence.endMinutes)
            }
            if !current.isEmpty { groups.append(current) }

            return groups.flatMap { group -> [CalendarOccurrencePlacement] in
                var laneEnds: [Int] = []
                var assigned: [(CalendarOccurrence, Int)] = []
                for occurrence in group {
                    let lane = laneEnds.firstIndex(where: { $0 <= occurrence.startMinutes }) ?? laneEnds.count
                    if lane == laneEnds.count { laneEnds.append(occurrence.endMinutes) } else { laneEnds[lane] = occurrence.endMinutes }
                    assigned.append((occurrence, lane))
                }
                return assigned.map { CalendarOccurrencePlacement(occurrence: $0.0, lane: $0.1, laneCount: laneEnds.count) }
            }
        }
    }

    static func startOfWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        var calendar = calendar
        calendar.firstWeekday = 2
        return calendar.dateInterval(of: .weekOfYear, for: date)!.start
    }

    static func occurrences(
        courses: [ClassCourse], sessions: [ClassSession], week: Date, calendar: Calendar = .current
    ) -> [CalendarOccurrence] {
        let start = startOfWeek(containing: week, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start)!
        let overrides = sessions.filter { $0.originalDate != nil }
        var result: [CalendarOccurrence] = []

        for course in courses {
            for offset in 0..<7 {
                let day = calendar.date(byAdding: .day, value: offset, to: start)!
                guard isScheduled(course, on: day, calendar: calendar) else { continue }
                if let session = overrides.first(where: {
                    $0.classID == course.id && calendar.isDate($0.originalDate!, inSameDayAs: day)
                }) {
                    if session.isCancelled != true, session.date >= start, session.date < end {
                        result.append(occurrence(course: course, session: session, originalDate: day))
                    }
                } else {
                    result.append(CalendarOccurrence(
                        id: "\(course.id.uuidString)-\(day.timeIntervalSinceReferenceDate)", course: course,
                        date: day, originalDate: day, startMinutes: course.startMinutes,
                        endMinutes: course.endMinutes, session: nil
                    ))
                }
            }
        }

        for session in overrides where session.date >= start && session.date < end {
            guard session.isCancelled != true,
                  !result.contains(where: { $0.session?.id == session.id }),
                  let course = courses.first(where: { $0.id == session.classID }) else { continue }
            result.append(occurrence(course: course, session: session, originalDate: session.originalDate ?? session.date))
        }
        return result.sorted { $0.date == $1.date ? $0.startMinutes < $1.startMinutes : $0.date < $1.date }
    }

    private static func occurrence(course: ClassCourse, session: ClassSession, originalDate: Date) -> CalendarOccurrence {
        CalendarOccurrence(
            id: session.id.uuidString, course: course, date: session.date, originalDate: originalDate,
            startMinutes: session.startMinutesSnapshot ?? course.startMinutes,
            endMinutes: session.endMinutesSnapshot ?? course.endMinutes, session: session
        )
    }

    private static func isScheduled(_ course: ClassCourse, on date: Date, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        let starts = calendar.startOfDay(for: course.startDate)
        guard day >= starts else { return false }
        if let endDate = course.endDate, day > calendar.startOfDay(for: endDate) { return false }
        if course.recurrence == "Every week" {
            return calendar.component(.weekday, from: day) == course.weekday.rawValue
        }
        return calendar.isDate(day, inSameDayAs: starts)
    }
}
