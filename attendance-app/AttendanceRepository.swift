import Foundation
import Combine

@MainActor
protocol AttendanceRepository: AnyObject {
    var students: [Student] { get }
    var classes: [ClassCourse] { get }
    var enrollments: [Enrollment] { get }
    var sessions: [ClassSession] { get }
    var attendance: [AttendanceRecord] { get }
    var makeupCredits: [MakeupCredit] { get }

    func addStudent(_ student: Student)
    func addClass(_ course: ClassCourse)
    func updateClass(_ course: ClassCourse)
    func removeClass(id: UUID)
    func setEnrollment(studentID: UUID, classID: UUID, assigned: Bool)
    func session(for course: ClassCourse, on date: Date) -> ClassSession
    func saveAttendance(sessionID: UUID, records: [AttendanceRecord])
    func addStudent(_ studentID: UUID, to sessionID: UUID)
    func resetAllData()
}

private struct LocalSnapshot: Codable {
    var students: [Student] = []
    var classes: [ClassCourse] = []
    var enrollments: [Enrollment] = []
    var sessions: [ClassSession] = []
    var attendance: [AttendanceRecord] = []
    var makeupCredits: [MakeupCredit] = []
    var setupComplete = false
    var onboardingStarted: Bool? = nil
}

@MainActor
final class LocalAttendanceRepository: ObservableObject, AttendanceRepository {
    @Published private(set) var students: [Student]
    @Published private(set) var classes: [ClassCourse]
    @Published private(set) var enrollments: [Enrollment]
    @Published private(set) var sessions: [ClassSession]
    @Published private(set) var attendance: [AttendanceRecord]
    @Published private(set) var makeupCredits: [MakeupCredit]
    @Published var setupComplete: Bool {
        didSet { persist() }
    }
    @Published var onboardingStarted: Bool {
        didSet { persist() }
    }

    private let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL
        let snapshot = Self.load(from: self.storageURL)
        students = snapshot.students
        classes = snapshot.classes
        enrollments = snapshot.enrollments
        sessions = snapshot.sessions
        attendance = snapshot.attendance
        makeupCredits = snapshot.makeupCredits
        setupComplete = snapshot.setupComplete
        onboardingStarted = snapshot.onboardingStarted
            ?? (snapshot.setupComplete || !snapshot.classes.isEmpty || !snapshot.students.isEmpty)
    }

    private static var defaultStorageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("AttendanceApp", isDirectory: true).appendingPathComponent("local-data.json")
    }

    private static func load(from url: URL) -> LocalSnapshot {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(LocalSnapshot.self, from: data) else {
            return LocalSnapshot()
        }
        return snapshot
    }

    private func persist() {
        let snapshot = LocalSnapshot(
            students: students,
            classes: classes,
            enrollments: enrollments,
            sessions: sessions,
            attendance: attendance,
            makeupCredits: makeupCredits,
            setupComplete: setupComplete,
            onboardingStarted: onboardingStarted
        )
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            assertionFailure("Unable to persist local attendance data: \(error)")
        }
    }

    func addStudent(_ student: Student) {
        students.append(student)
        persist()
    }

    func addClass(_ course: ClassCourse) {
        classes.append(course)
        persist()
    }

    func updateClass(_ course: ClassCourse) {
        guard let index = classes.firstIndex(where: { $0.id == course.id }) else { return }
        classes[index] = course
        persist()
    }

    func removeClass(id: UUID) {
        classes.removeAll { $0.id == id }
        persist()
    }

    func setEnrollment(studentID: UUID, classID: UUID, assigned: Bool) {
        if assigned {
            guard !enrollments.contains(where: { $0.studentID == studentID && $0.classID == classID }) else { return }
            let course = classes.first { $0.id == classID }
            enrollments.append(Enrollment(
                studentID: studentID,
                classID: classID,
                classNameSnapshot: course?.displayName,
                weekdaySnapshot: course?.weekday,
                startMinutesSnapshot: course?.startMinutes,
                endMinutesSnapshot: course?.endMinutes
            ))
        } else {
            enrollments.removeAll { $0.studentID == studentID && $0.classID == classID }
        }
        persist()
    }

    func session(for course: ClassCourse, on date: Date = .now) -> ClassSession {
        let day = Calendar.current.startOfDay(for: date)
        if let existing = sessions.first(where: { $0.classID == course.id && Calendar.current.isDate($0.date, inSameDayAs: day) }) {
            return existing
        }
        let new = ClassSession(
            classID: course.id,
            date: day,
            classNameSnapshot: course.displayName,
            startMinutesSnapshot: course.startMinutes,
            endMinutesSnapshot: course.endMinutes
        )
        sessions.append(new)
        persist()
        return new
    }

    func saveAttendance(sessionID: UUID, records: [AttendanceRecord]) {
        attendance.removeAll { $0.sessionID == sessionID }
        attendance.append(contentsOf: records)
        if let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[sessionIndex].isComplete = true
            let savedSession = sessions[sessionIndex]
            for record in records where record.status == .absent {
                let alreadyExists = makeupCredits.contains {
                    $0.studentID == record.studentID &&
                    $0.sourceClassID == savedSession.classID &&
                    Calendar.current.isDate($0.missedDate, inSameDayAs: savedSession.date)
                }
                if !alreadyExists {
                    makeupCredits.append(MakeupCredit(
                        studentID: record.studentID,
                        sourceClassID: savedSession.classID,
                        missedDate: savedSession.date,
                        state: .owed
                    ))
                }
            }
        }
        for record in records where record.status == .makeup || record.status == .present {
            if let index = makeupCredits.firstIndex(where: {
                $0.studentID == record.studentID &&
                $0.scheduledSessionID == sessionID &&
                $0.state == .scheduled
            }) {
                makeupCredits[index].state = .completed
            }
        }
        persist()
    }

    func addStudent(_ studentID: UUID, to sessionID: UUID) {
        if let index = makeupCredits.firstIndex(where: {
            $0.studentID == studentID && ($0.state == .owed || $0.state == .scheduled)
        }) {
            makeupCredits[index].state = .scheduled
            makeupCredits[index].scheduledSessionID = sessionID
            persist()
        }
    }

    func students(in classID: UUID) -> [Student] {
        let ids = Set(enrollments.filter { $0.classID == classID }.map(\.studentID))
        return students.filter { ids.contains($0.id) }
    }

    func resetAllData() {
        students = []
        classes = []
        enrollments = []
        sessions = []
        attendance = []
        makeupCredits = []
        setupComplete = false
        onboardingStarted = false
        try? FileManager.default.removeItem(at: storageURL)
    }
}
