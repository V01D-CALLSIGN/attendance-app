import Foundation
import SwiftUI

enum Weekday: Int, CaseIterable, Codable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    var id: Int { rawValue }
    var name: String { Calendar.current.weekdaySymbols[rawValue - 1] }
    var short: String { String(name.prefix(3)) }
    static let mondayFirst: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
}

enum ClassType: String, CaseIterable, Codable, Identifiable {
    case art = "Art"
    case study = "Study"
    var id: String { rawValue }
}

enum GradeOption: String, CaseIterable, Codable, Identifiable {
    case preK = "Pre-K"
    case kindergarten = "Kindergarten"
    case grade1 = "Grade 1"
    case grade2 = "Grade 2"
    case grade3 = "Grade 3"
    case grade4 = "Grade 4"
    case grade5 = "Grade 5"
    case grade6 = "Grade 6"
    case grade7 = "Grade 7"
    case grade8 = "Grade 8"
    case grade9 = "Grade 9"
    case grade10 = "Grade 10"
    case grade11 = "Grade 11"
    case grade12 = "Grade 12"
    var id: String { rawValue }
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
    var emergencyContact: String? = nil
    var photoData: Data? = nil
    var isActive: Bool? = nil
    var fullName: String { "\(firstName) \(lastName)" }
    var initials: String { "\(firstName.first.map(String.init) ?? "")\(lastName.first.map(String.init) ?? "")".uppercased() }
    var gradeLabel: String {
        grade.hasPrefix("Grade") || grade == "Pre-K" || grade == "Kindergarten" ? grade : "Grade \(grade)"
    }
    var active: Bool { isActive ?? true }
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
    var notes: String? = nil

    var displayName: String { "\(name) Class \(weekday.name)" }
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
    var classNameSnapshot: String? = nil
    var weekdaySnapshot: Weekday? = nil
    var startMinutesSnapshot: Int? = nil
    var endMinutesSnapshot: Int? = nil
}

struct ClassSession: Identifiable, Hashable, Codable {
    var id = UUID()
    let classID: UUID
    var date: Date
    var originalDate: Date? = nil
    var isComplete = false
    var classNameSnapshot: String? = nil
    var startMinutesSnapshot: Int? = nil
    var endMinutesSnapshot: Int? = nil
    var isCancelled: Bool? = nil
    var locationSnapshot: String? = nil
    var recurrenceSnapshot: String? = nil
    var notesSnapshot: String? = nil
    var isMakeupClassSnapshot: Bool? = nil

    func displayName(classes: [ClassCourse]) -> String {
        classNameSnapshot ?? classes.first(where: { $0.id == classID })?.displayName ?? "Archived Class"
    }

    func timeLabel(classes: [ClassCourse]) -> String {
        if let startMinutesSnapshot, let endMinutesSnapshot {
            return ClassCourse(
                name: "", weekday: .monday, startMinutes: startMinutesSnapshot,
                endMinutes: endMinutesSnapshot, location: "", color: .blue
            ).timeLabel
        }
        return classes.first(where: { $0.id == classID })?.timeLabel ?? "Time unavailable"
    }
}

enum RecurrenceEditScope: String, CaseIterable, Identifiable {
    case thisOnly = "This class only"
    case thisAndFuture = "This and future classes"
    case every = "Every class in the series"
    var id: String { rawValue }
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
