import Foundation
import SwiftUI

enum Weekday: Int, CaseIterable, Codable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    var id: Int { rawValue }
    var name: String { Calendar.current.weekdaySymbols[rawValue - 1] }
    var short: String { String(name.prefix(3)) }
}

enum ClassColor: String, CaseIterable, Codable, Identifiable {
    case coral, violet, blue, mint, amber
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .coral: Color(red: 0.96, green: 0.42, blue: 0.35)
        case .violet: Color(red: 0.48, green: 0.36, blue: 0.85)
        case .blue: Color(red: 0.20, green: 0.52, blue: 0.91)
        case .mint: Color(red: 0.19, green: 0.67, blue: 0.55)
        case .amber: Color(red: 0.95, green: 0.65, blue: 0.20)
        }
    }
}

struct Student: Identifiable, Hashable, Codable {
    var id = UUID()
    var firstName: String
    var lastName: String
    var grade: String
    var contact: String = ""
    var notes: String = ""
    var fullName: String { "\(firstName) \(lastName)" }
    var initials: String { "\(firstName.first.map(String.init) ?? "")\(lastName.first.map(String.init) ?? "")".uppercased() }
}

struct ClassCourse: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var weekday: Weekday
    var startMinutes: Int
    var endMinutes: Int
    var recurrence: String = "Every week"
    var startDate: Date = .now
    var endDate: Date? = nil
    var location: String
    var color: ClassColor
    var isMakeupClass = false

    var timeLabel: String { "\(Self.time(startMinutes))–\(Self.time(endMinutes))" }
    private static func time(_ minutes: Int) -> String {
        let hour = minutes / 60, minute = minutes % 60
        let display = hour % 12 == 0 ? 12 : hour % 12
        return minute == 0 ? "\(display):00 \(hour < 12 ? "AM" : "PM")" : String(format: "%d:%02d %@", display, minute, hour < 12 ? "AM" : "PM")
    }
}

struct Enrollment: Identifiable, Hashable, Codable {
    var id = UUID()
    let studentID: UUID
    let classID: UUID
    var startsOn: Date = .now
    var endsOn: Date? = nil
}

struct ClassSession: Identifiable, Hashable, Codable {
    var id = UUID()
    let classID: UUID
    let date: Date
    var isComplete = false
}

enum AttendanceStatus: String, CaseIterable, Codable, Identifiable {
    case unmarked, present, absent, late, excused, makeup
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .unmarked: "circle"
        case .present: "checkmark"
        case .absent: "xmark"
        case .late: "clock"
        case .excused: "e.circle"
        case .makeup: "arrow.triangle.2.circlepath"
        }
    }
}

struct AttendanceRecord: Identifiable, Hashable, Codable {
    var id = UUID()
    let sessionID: UUID
    let studentID: UUID
    var status: AttendanceStatus
    var notes = ""
    var lateArrival: Date? = nil
}

enum MakeupCreditState: String, CaseIterable, Codable {
    case owed, scheduled, completed, waived, expired
    var label: String { rawValue.capitalized }
}

struct MakeupCredit: Identifiable, Hashable, Codable {
    var id = UUID()
    let studentID: UUID
    let sourceClassID: UUID
    let missedDate: Date
    var state: MakeupCreditState
    var scheduledSessionID: UUID? = nil
    var expiresOn: Date? = nil
}
