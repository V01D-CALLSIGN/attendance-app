import Foundation

struct StudentMonthReport {
    let student: Student
    let month: Date
    let eligibleSessions: [ClassSession]
    let records: [AttendanceRecord]
    let classNames: [String]
    let makeupCompleted: Int
    let attendedSessions: Int

    var uniqueDays: Int { Set(eligibleSessions.map { Calendar.current.startOfDay(for: $0.date) }).count }
    var present: Int { records.filter { $0.status == .present }.count }
    var absent: Int { records.filter { $0.status == .absent }.count }
    var late: Int { records.filter { $0.status == .late }.count }
    var excused: Int { records.filter { $0.status == .excused }.count }
    var attended: Int { attendedSessions }
    var percentage: Double? {
        eligibleSessions.isEmpty ? nil : Double(attended) / Double(eligibleSessions.count) * 100
    }

    func records(on date: Date) -> [AttendanceRecord] {
        let sessionIDs = Set(eligibleSessions.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }.map(\.id))
        return records.filter { sessionIDs.contains($0.sessionID) }
    }
}

enum ReportCalculator {
    static func report(
        student: Student,
        month: Date,
        classes: [ClassCourse],
        enrollments: [Enrollment],
        sessions: [ClassSession],
        attendance: [AttendanceRecord],
        makeupCredits: [MakeupCredit]
    ) -> StudentMonthReport {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: month)!
        let studentRecords = attendance.filter { $0.studentID == student.id }
        let recordedSessionIDs = Set(studentRecords.map(\.sessionID))
        let studentEnrollments = enrollments.filter { $0.studentID == student.id }

        var candidateSessions = sessions.filter { interval.contains($0.date) }
        for enrollment in studentEnrollments {
            let course = classes.first { $0.id == enrollment.classID }
            guard let weekday = enrollment.weekdaySnapshot ?? course?.weekday else { continue }
            let start = max(interval.start, calendar.startOfDay(for: enrollment.startsOn))
            let enrollmentEnd = enrollment.endsOn
                .flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
                ?? interval.end
            let end = min(interval.end, enrollmentEnd)
            guard start < end else { continue }
            var date = start
            while date < end {
                if calendar.component(.weekday, from: date) == weekday.rawValue,
                   !candidateSessions.contains(where: {
                       $0.classID == enrollment.classID && calendar.isDate($0.date, inSameDayAs: date)
                   }) {
                    candidateSessions.append(ClassSession(
                        classID: enrollment.classID,
                        date: date,
                        classNameSnapshot: enrollment.classNameSnapshot ?? course?.displayName,
                        startMinutesSnapshot: enrollment.startMinutesSnapshot ?? course?.startMinutes,
                        endMinutesSnapshot: enrollment.endMinutesSnapshot ?? course?.endMinutes
                    ))
                }
                date = calendar.date(byAdding: .day, value: 1, to: date)!
            }
        }

        let eligible = candidateSessions.filter { session in
            guard session.isCancelled != true, interval.contains(session.date) else { return false }
            if recordedSessionIDs.contains(session.id) { return true }
            return studentEnrollments.contains { enrollment in
                guard enrollment.classID == session.classID else { return false }
                let sessionDay = calendar.startOfDay(for: session.date)
                let starts = calendar.startOfDay(for: enrollment.startsOn)
                let ends = enrollment.endsOn.map { calendar.startOfDay(for: $0) }
                return starts <= sessionDay && (ends == nil || sessionDay <= ends!)
            }
        }.sorted { $0.date < $1.date }

        let eligibleIDs = Set(eligible.map(\.id))
        let records = studentRecords.filter { eligibleIDs.contains($0.sessionID) }
        let makeupSessionIDs = Set(records.filter { $0.status == .makeup }.map(\.sessionID))
        let creditedSessions = Set(makeupCredits.compactMap { credit -> UUID? in
            guard credit.studentID == student.id,
                  credit.state == .completed,
                  let sessionID = credit.scheduledSessionID,
                  eligibleIDs.contains(sessionID) else { return nil }
            return sessionID
        })
        let presentSessionIDs = Set(records.filter { $0.status == .present }.map(\.sessionID))
        let makeupCompletedIDs = makeupSessionIDs.union(creditedSessions)
        let names = Set(eligible.map { $0.displayName(classes: classes) })

        return StudentMonthReport(
            student: student,
            month: interval.start,
            eligibleSessions: eligible,
            records: records,
            classNames: names.sorted(),
            makeupCompleted: makeupCompletedIDs.count,
            attendedSessions: presentSessionIDs.union(makeupCompletedIDs).count
        )
    }
}
