import SwiftUI

struct ReportsView: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @State private var selectedMonth = Calendar.current.date(
        byAdding: .month,
        value: -1,
        to: Calendar.current.dateInterval(of: .month, for: .now)!.start
    )!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MonthSelector(month: $selectedMonth, canMoveForward: canMoveForward)
                Text("Monthly student overview")
                    .font(.title2.bold())
                if repo.students.isEmpty {
                    EmptyStateView(
                        icon: "chart.bar",
                        title: "No attendance data yet",
                        message: "Add students and save attendance to build monthly reports."
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(repo.students) { student in
                            let report = report(for: student)
                            NavigationLink {
                                StudentMonthlyReportView(student: student, month: selectedMonth)
                            } label: {
                                StudentReportCard(report: report)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(AppTheme.background)
        .navigationTitle("Reports")
        .gesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                if value.translation.width > 70 { moveMonth(-1) }
                if value.translation.width < -70 && canMoveForward { moveMonth(1) }
            }
        )
    }

    private var canMoveForward: Bool {
        let next = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth)!
        let current = Calendar.current.dateInterval(of: .month, for: .now)!.start
        if next <= current { return true }
        return repo.sessions.contains { Calendar.current.isDate($0.date, equalTo: next, toGranularity: .month) }
    }

    private func moveMonth(_ amount: Int) {
        guard amount < 0 || canMoveForward else { return }
        selectedMonth = Calendar.current.date(byAdding: .month, value: amount, to: selectedMonth)!
    }

    private func report(for student: Student) -> StudentMonthReport {
        ReportCalculator.report(
            student: student, month: selectedMonth, classes: repo.classes,
            enrollments: repo.enrollments, sessions: repo.sessions,
            attendance: repo.attendance, makeupCredits: repo.makeupCredits
        )
    }
}

private struct MonthSelector: View {
    @Binding var month: Date
    let canMoveForward: Bool
    var body: some View {
        HStack {
            Button { move(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.title3.bold())
                Text("Swipe to change month")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
            Button { move(1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(!canMoveForward)
        }
        .cardStyle()
    }
    private func move(_ amount: Int) {
        guard amount < 0 || canMoveForward else { return }
        month = Calendar.current.date(byAdding: .month, value: amount, to: month)!
    }
}

private struct StudentReportCard: View {
    let report: StudentMonthReport
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                AvatarView(student: report.student)
                VStack(alignment: .leading) {
                    Text(report.student.fullName).font(.headline)
                    Text(report.student.gradeLabel).font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Text(report.percentage.map { "\(Int($0.rounded()))%" } ?? "No data")
                    .font(.headline)
                    .foregroundStyle(report.percentage == nil ? AppTheme.muted : AppTheme.deep)
                Image(systemName: "chevron.right").foregroundStyle(.gray)
            }
            HStack {
                ReportMetric(value: report.eligibleSessions.count, label: "Eligible sessions")
                ReportMetric(value: report.uniqueDays, label: "Unique days")
                ReportMetric(value: report.present, label: "Present")
                ReportMetric(value: report.absent, label: "Absent")
            }
            if report.percentage == nil {
                Text("No attendance data")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .cardStyle()
    }
}

private struct ReportMetric: View {
    let value: Int
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.headline)
            Text(label).font(.system(size: 9)).foregroundStyle(AppTheme.muted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StudentMonthlyReportView: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    let student: Student
    let month: Date

    private var report: StudentMonthReport {
        ReportCalculator.report(
            student: student, month: month, classes: repo.classes,
            enrollments: repo.enrollments, sessions: repo.sessions,
            attendance: repo.attendance, makeupCredits: repo.makeupCredits
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    AvatarView(student: student, size: 64)
                    VStack(alignment: .leading) {
                        Text(student.fullName).font(.title2.bold())
                        Text(student.gradeLabel).foregroundStyle(AppTheme.muted)
                        Text(month.formatted(.dateTime.month(.wide).year())).font(.subheadline.weight(.semibold))
                    }
                }
                HStack {
                    ReportMetric(value: report.eligibleSessions.count, label: "Eligible sessions")
                    ReportMetric(value: report.uniqueDays, label: "Unique class days")
                    VStack(alignment: .leading) {
                        Text(report.percentage.map { "\(Int($0.rounded()))%" } ?? "—").font(.headline)
                        Text(report.percentage == nil ? "No attendance data" : "Attendance").font(.system(size: 9)).foregroundStyle(AppTheme.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.cardStyle()
                HStack {
                    ReportMetric(value: report.present, label: "Present")
                    ReportMetric(value: report.absent, label: "Absent")
                    ReportMetric(value: report.late, label: "Late")
                    ReportMetric(value: report.excused, label: "Excused")
                    ReportMetric(value: report.makeupCompleted, label: "Makeup")
                }.cardStyle()
                VStack(alignment: .leading, spacing: 8) {
                    Text("ENROLLED CLASSES").font(.caption.bold()).tracking(1.1).foregroundStyle(AppTheme.muted)
                    if report.classNames.isEmpty {
                        Text("No classes in this report.")
                    } else {
                        ForEach(report.classNames, id: \.self) { Label($0, systemImage: "book.closed") }
                    }
                }.cardStyle()
                Text("Attendance calendar").font(.title3.bold())
                MonthlyAttendanceCalendar(report: report, classes: repo.classes)
                CalendarLegend()
            }
            .padding(20)
        }
        .background(AppTheme.background)
        .navigationTitle("Student report")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MonthlyAttendanceCalendar: View {
    let report: StudentMonthReport
    let classes: [ClassCourse]
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, label in
                    Text(label).font(.caption.bold()).frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                NavigationLink {
                    WeeklyStudentReportView(student: report.student, month: report.month, weekDates: week.compactMap { $0 })
                } label: {
                    HStack(spacing: 5) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                            DayReportCell(date: date, report: report)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }

    private var weeks: [[Date?]] {
        let interval = calendar.dateInterval(of: .month, for: report.month)!
        let range = calendar.range(of: .day, in: .month, for: report.month)!
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday + 5) % 7
        var values: [Date?] = Array(repeating: nil, count: leading)
        values += range.map { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start)! }
        while values.count % 7 != 0 { values.append(nil) }
        return stride(from: 0, to: values.count, by: 7).map { Array(values[$0..<$0 + 7]) }
    }
}

private struct DayReportCell: View {
    let date: Date?
    let report: StudentMonthReport
    var body: some View {
        if let date {
            let records = report.records(on: date)
            let scheduled = report.eligibleSessions.contains { Calendar.current.isDate($0.date, inSameDayAs: date) }
            VStack(spacing: 3) {
                Text("\(Calendar.current.component(.day, from: date))").font(.caption)
                Text(markers(records: records, scheduled: scheduled))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(markerColor(records: records))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(scheduled ? markerColor(records: records).opacity(0.1) : Color.gray.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: 42)
        }
    }

    private func markers(records: [AttendanceRecord], scheduled: Bool) -> String {
        guard scheduled else { return "–" }
        guard !records.isEmpty else { return "S" }
        return records.map {
            switch $0.status {
            case .present: "P"
            case .absent: "A"
            case .late: "L"
            case .excused: "E"
            case .makeup: "M"
            case .unmarked: "S"
            }
        }.joined()
    }

    private func markerColor(records: [AttendanceRecord]) -> Color {
        guard let status = records.first?.status else { return AppTheme.muted }
        switch status {
        case .present: return .green
        case .absent: return .red
        case .late: return .orange
        case .excused: return .blue
        case .makeup: return AppTheme.deep
        case .unmarked: return AppTheme.muted
        }
    }
}

private struct CalendarLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("P Present · A Absent · L Late")
            Text("E Excused · M Makeup · S Scheduled")
            Text("– No scheduled class")
        }
        .font(.caption)
        .foregroundStyle(AppTheme.muted)
    }
}

struct WeeklyStudentReportView: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    let student: Student
    let month: Date
    let weekDates: [Date]

    private var report: StudentMonthReport {
        ReportCalculator.report(
            student: student, month: month, classes: repo.classes,
            enrollments: repo.enrollments, sessions: repo.sessions,
            attendance: repo.attendance, makeupCredits: repo.makeupCredits
        )
    }

    private var weekSessions: [ClassSession] {
        guard let first = weekDates.first, let last = weekDates.last else { return [] }
        return report.eligibleSessions.filter {
            Calendar.current.startOfDay(for: $0.date) >= Calendar.current.startOfDay(for: first) &&
            Calendar.current.startOfDay(for: $0.date) <= Calendar.current.startOfDay(for: last)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if weekSessions.isEmpty {
                    EmptyStateView(icon: "calendar", title: "No scheduled classes this week.", message: "There are no eligible sessions for \(student.fullName).")
                } else {
                    ForEach(weekSessions) { session in
                        let record = report.records.first { $0.sessionID == session.id }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(session.date.formatted(.dateTime.weekday(.wide).month().day())).font(.headline)
                                    Text(session.displayName(classes: repo.classes)).font(.subheadline)
                                    Text(session.timeLabel(classes: repo.classes)).font(.caption).foregroundStyle(AppTheme.muted)
                                }
                                Spacer()
                                StatusBadge(status: record?.status ?? .unmarked)
                            }
                            if record?.status == .makeup {
                                Label("Makeup session", systemImage: "arrow.triangle.2.circlepath").font(.caption.weight(.semibold))
                            }
                            if let notes = record?.notes, !notes.isEmpty {
                                Label(notes, systemImage: "note.text").font(.subheadline)
                            }
                        }
                        .cardStyle()
                    }
                }
            }
            .padding(20)
        }
        .background(AppTheme.background)
        .navigationTitle("Weekly attendance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StatusBadge: View {
    let status: AttendanceStatus
    var body: some View {
        Label(status == .unmarked ? "Scheduled" : status.label, systemImage: status.icon)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.deep.opacity(0.1))
            .foregroundStyle(AppTheme.deep)
            .clipShape(Capsule())
    }
}
