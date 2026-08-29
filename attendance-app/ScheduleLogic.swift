import Foundation

enum ScheduleLogic {
    static func nextClass(
        from classes: [ClassCourse],
        at date: Date,
        calendar: Calendar = .current
    ) -> ClassCourse? {
        let weekday = Weekday(rawValue: calendar.component(.weekday, from: date))
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return classes
            .filter { $0.weekday == weekday && $0.endMinutes > minutes }
            .sorted { $0.startMinutes < $1.startMinutes }
            .first
    }
}
