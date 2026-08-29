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
    func updateStudent(_ student: Student) -> Bool
    func deleteOrArchiveStudent(id: UUID) -> Bool
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
    @Published var lastError: String?
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
        lastError = nil
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

    @discardableResult
    private func persist() -> Bool {
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
            lastError = nil
            return true
        } catch {
            lastError = "Changes could not be saved. Please try again."
            return false
        }
    }

    func addStudent(_ student: Student) {
        students.append(student)
        persist()
    }

    @discardableResult
    func updateStudent(_ student: Student) -> Bool {
        guard let index = students.firstIndex(where: { $0.id == student.id }) else { return false }
        students[index] = student
        return persist()
    }

    @discardableResult
    func deleteOrArchiveStudent(id: UUID) -> Bool {
        let sessionIDs = Set(attendance.filter { $0.studentID == id }.map(\.sessionID))
        let hasHistory = !sessionIDs.isEmpty || makeupCredits.contains { $0.studentID == id }
        if hasHistory, let index = students.firstIndex(where: { $0.id == id }) {
            students[index].isActive = false
            enrollments = enrollments.map { enrollment in
                guard enrollment.studentID == id, enrollment.endsOn == nil else { return enrollment }
                var closed = enrollment
                closed.endsOn = Date.now
                return closed
            }
        } else {
            students.removeAll { $0.id == id }
            enrollments.removeAll { $0.studentID == id }
            makeupCredits.removeAll { $0.studentID == id }
        }
        return persist()
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

    @discardableResult
    func createClass(_ course: ClassCourse, assignedStudentIDs: Set<UUID>) -> Bool {
        guard !classes.contains(where: { $0.id == course.id }) else { return false }
        classes.append(course)
        for studentID in assignedStudentIDs {
            enrollments.append(enrollment(studentID: studentID, course: course, startsOn: course.startDate))
        }
        return persist()
    }

    @discardableResult
    func saveClassEdit(
        original: ClassCourse,
        edited: ClassCourse,
        occurrenceDate: Date,
        scope: RecurrenceEditScope,
        assignedStudentIDs: Set<UUID>
    ) -> Bool {
        let calendar = Calendar.current
        let occurrenceDay = calendar.startOfDay(for: occurrenceDate)
        switch scope {
        case .thisOnly:
            let originalDay = occurrenceDay
            let sessionIndex: Int
            if let existing = sessions.firstIndex(where: {
                $0.classID == original.id && calendar.isDate($0.originalDate ?? $0.date, inSameDayAs: originalDay)
            }) {
                sessionIndex = existing
            } else {
                sessions.append(ClassSession(classID: original.id, date: originalDay, originalDate: originalDay))
                sessionIndex = sessions.count - 1
            }
            let movedDay = calendar.startOfDay(for: edited.startDate)
            sessions[sessionIndex].date = movedDay
            sessions[sessionIndex].originalDate = originalDay
            sessions[sessionIndex].classNameSnapshot = Self.displayName(type: edited.name, date: movedDay)
            sessions[sessionIndex].startMinutesSnapshot = edited.startMinutes
            sessions[sessionIndex].endMinutesSnapshot = edited.endMinutes
            sessions[sessionIndex].locationSnapshot = edited.location
            sessions[sessionIndex].recurrenceSnapshot = edited.recurrence
            sessions[sessionIndex].notesSnapshot = edited.notes
            sessions[sessionIndex].isMakeupClassSnapshot = edited.isMakeupClass
            sessions[sessionIndex].isCancelled = false
            synchronizeEnrollments(classID: original.id, studentIDs: assignedStudentIDs, startsOn: original.startDate)
        case .thisAndFuture:
            guard let oldIndex = classes.firstIndex(where: { $0.id == original.id }) else { return false }
            let previousDay = calendar.date(byAdding: .day, value: -1, to: occurrenceDay)!
            classes[oldIndex].endDate = previousDay
            for index in enrollments.indices where enrollments[index].classID == original.id && enrollments[index].endsOn == nil {
                enrollments[index].endsOn = previousDay
            }
            var future = edited
            future.id = UUID()
            future.startDate = calendar.startOfDay(for: edited.startDate)
            future.weekday = Self.weekday(for: future.startDate)
            classes.append(future)
            for studentID in assignedStudentIDs {
                enrollments.append(enrollment(studentID: studentID, course: future, startsOn: future.startDate))
            }
        case .every:
            guard let index = classes.firstIndex(where: { $0.id == original.id }) else { return false }
            var replacement = edited
            replacement.id = original.id
            replacement.startDate = original.startDate
            replacement.weekday = Self.weekday(for: edited.startDate)
            classes[index] = replacement
            synchronizeEnrollments(classID: original.id, studentIDs: assignedStudentIDs, startsOn: replacement.startDate)
        }
        return persist()
    }

    @discardableResult
    func deleteClass(_ course: ClassCourse, occurrenceDate: Date, scope: RecurrenceEditScope) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: occurrenceDate)
        switch scope {
        case .thisOnly:
            let index: Int
            if let existing = sessions.firstIndex(where: {
                $0.classID == course.id && calendar.isDate($0.originalDate ?? $0.date, inSameDayAs: day)
            }) {
                index = existing
            } else {
                sessions.append(ClassSession(classID: course.id, date: day, originalDate: day))
                index = sessions.count - 1
            }
            sessions[index].isCancelled = true
        case .thisAndFuture:
            guard let index = classes.firstIndex(where: { $0.id == course.id }) else { return false }
            let previousDay = calendar.date(byAdding: .day, value: -1, to: day)!
            classes[index].endDate = previousDay
            for index in enrollments.indices where enrollments[index].classID == course.id && enrollments[index].endsOn == nil {
                enrollments[index].endsOn = previousDay
            }
        case .every:
            classes.removeAll { $0.id == course.id }
            let previousDay = calendar.date(byAdding: .day, value: -1, to: day)!
            for index in enrollments.indices where enrollments[index].classID == course.id && enrollments[index].endsOn == nil {
                enrollments[index].endsOn = previousDay
            }
        }
        return persist()
    }

    func setEnrollment(studentID: UUID, classID: UUID, assigned: Bool) {
        if assigned {
            guard !enrollments.contains(where: { $0.studentID == studentID && $0.classID == classID && $0.endsOn == nil }) else { return }
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
            for index in enrollments.indices where enrollments[index].studentID == studentID && enrollments[index].classID == classID && enrollments[index].endsOn == nil {
                enrollments[index].endsOn = Date.now
            }
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
            originalDate: day,
            classNameSnapshot: course.displayName,
            startMinutesSnapshot: course.startMinutes,
            endMinutesSnapshot: course.endMinutes,
            locationSnapshot: course.location,
            recurrenceSnapshot: course.recurrence,
            notesSnapshot: course.notes,
            isMakeupClassSnapshot: course.isMakeupClass
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
        let ids = Set(enrollments.filter { $0.classID == classID && $0.endsOn == nil }.map(\.studentID))
        return students.filter { ids.contains($0.id) && $0.active }
    }

    func assignedStudentIDs(classID: UUID) -> Set<UUID> {
        Set(enrollments.filter { $0.classID == classID && $0.endsOn == nil }.map(\.studentID))
    }

    private func synchronizeEnrollments(classID: UUID, studentIDs: Set<UUID>, startsOn: Date) {
        for index in enrollments.indices where enrollments[index].classID == classID && enrollments[index].endsOn == nil && !studentIDs.contains(enrollments[index].studentID) {
            enrollments[index].endsOn = Date.now
        }
        guard let course = classes.first(where: { $0.id == classID }) else { return }
        let existing = Set(enrollments.filter { $0.classID == classID && $0.endsOn == nil }.map(\.studentID))
        for studentID in studentIDs.subtracting(existing) {
            enrollments.append(enrollment(studentID: studentID, course: course, startsOn: startsOn))
        }
    }

    private func enrollment(studentID: UUID, course: ClassCourse, startsOn: Date) -> Enrollment {
        Enrollment(
            studentID: studentID, classID: course.id, startsOn: startsOn,
            classNameSnapshot: course.displayName, weekdaySnapshot: course.weekday,
            startMinutesSnapshot: course.startMinutes, endMinutesSnapshot: course.endMinutes
        )
    }

    private static func weekday(for date: Date) -> Weekday {
        Weekday(rawValue: Calendar.current.component(.weekday, from: date)) ?? .monday
    }

    private static func displayName(type: String, date: Date) -> String {
        "\(type) Class \(weekday(for: date).name)"
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
