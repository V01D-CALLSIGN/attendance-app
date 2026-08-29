import SwiftUI

struct ClassRosterView: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @Environment(\.dismiss) private var dismiss
    let course: ClassCourse
    @State private var session: ClassSession?
    @State private var roster: [Student] = []
    @State private var records: [UUID: AttendanceRecord] = [:]
    @State private var undoStack: [[UUID: AttendanceRecord]] = []
    @State private var search = ""
    @State private var showPicker = false
    @State private var saved = false

    var filtered: [Student] { roster.filter { search.isEmpty || $0.fullName.localizedCaseInsensitiveContains(search) } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(course.isMakeupClass ? "MAKEUP SESSION" : "TODAY'S CLASS").font(.caption.bold()).tracking(1.3).foregroundStyle(.white.opacity(0.75))
                        Text(course.displayName).font(.system(size: 38, weight: .bold, design: .rounded))
                        HStack {
                            Label(course.timeLabel, systemImage: "clock")
                            if !course.location.isEmpty {
                                Label(course.location, systemImage: "mappin")
                            }
                        }.font(.subheadline)
                        Text(Date.now.formatted(date: .complete, time: .omitted)).font(.subheadline)
                    }.foregroundStyle(.white).padding(22).frame(maxWidth: .infinity, alignment: .leading).background(course.color.color.gradient).clipShape(RoundedRectangle(cornerRadius: 28))
                    HStack {
                        Text("\(roster.count) students").font(.title3.bold())
                        Spacer()
                        if !undoStack.isEmpty { Button { undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.font(.subheadline.weight(.semibold)) }
                    }
                    HStack {
                        Button { markAllPresent() } label: { Label("Mark all present", systemImage: "checkmark.circle.fill") }
                            .buttonStyle(.borderedProminent).tint(course.color.color)
                        Spacer()
                        Text("\(records.values.filter { $0.status != .unmarked }.count)/\(roster.count) marked").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.muted)
                    }
                    TextField("Search this roster", text: $search).textFieldStyle(.roundedBorder)
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { student in
                            AttendanceRow(student: student, record: binding(for: student), tint: course.color.color) { snapshot() }
                        }
                    }
                    Button { showPicker = true } label: { Label("Add Student", systemImage: "person.badge.plus").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).controlSize(.large)
                }.padding(16).padding(.bottom, 90)
            }
            VStack {
                Button(saved ? "Attendance Saved" : "Save Attendance") { save() }
                    .buttonStyle(PrimaryButtonStyle()).disabled(session == nil)
            }.padding(.horizontal, 20).padding(.vertical, 12).background(.ultraThinMaterial)
        }.background(AppTheme.background).navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPicker) {
                if let session { StudentPicker(course: course, session: session, rosterIDs: Set(roster.map(\.id))) { selected in add(selected) } }
            }
            .onAppear { load() }
    }

    private func load() {
        let active = repo.session(for: course)
        session = active
        roster = repo.students(in: course.id)
        records = Dictionary(uniqueKeysWithValues: roster.map { student in
            let existing = repo.attendance.first { $0.sessionID == active.id && $0.studentID == student.id }
            return (student.id, existing ?? AttendanceRecord(sessionID: active.id, studentID: student.id, status: .unmarked))
        })
    }
    private func binding(for student: Student) -> Binding<AttendanceRecord> {
        Binding(get: { records[student.id] ?? AttendanceRecord(sessionID: session!.id, studentID: student.id, status: .unmarked) }, set: { records[student.id] = $0; saved = false })
    }
    private func snapshot() { undoStack.append(records); if undoStack.count > 10 { undoStack.removeFirst() } }
    private func undo() { if let previous = undoStack.popLast() { records = previous } }
    private func markAllPresent() { snapshot(); for student in roster { records[student.id]?.status = .present }; saved = false }
    private func save() { guard let session else { return }; repo.saveAttendance(sessionID: session.id, records: Array(records.values)); withAnimation { saved = true } }
    private func add(_ selected: [Student]) {
        guard let session else { return }
        for student in selected where !roster.contains(student) {
            roster.append(student)
            records[student.id] = AttendanceRecord(sessionID: session.id, studentID: student.id, status: course.isMakeupClass ? .makeup : .unmarked)
            if course.isMakeupClass { repo.addStudent(student.id, to: session.id) }
            else { repo.setEnrollment(studentID: student.id, classID: course.id, assigned: true) }
        }
    }
}

private struct AttendanceRow: View {
    let student: Student
    @Binding var record: AttendanceRecord
    let tint: Color
    let beforeChange: () -> Void
    @State private var expanded = false
    @State private var showNote = false
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                AvatarView(student: student)
                VStack(alignment: .leading, spacing: 3) { Text(student.fullName).font(.headline); Text(student.gradeLabel).font(.caption).foregroundStyle(AppTheme.muted) }
                Spacer()
                Button {
                    beforeChange()
                    if record.status == .unmarked { record.status = .present } else { expanded.toggle() }
                } label: {
                    Image(systemName: record.status.icon).font(.headline).frame(width: 44, height: 44)
                        .background(record.status == .unmarked ? Color.gray.opacity(0.1) : tint)
                        .foregroundStyle(record.status == .unmarked ? .gray : .white).clipShape(Circle())
                }
            }
            if expanded {
                HStack(spacing: 7) {
                    ForEach(AttendanceStatus.allCases.filter { $0 != .unmarked }) { status in
                        Button {
                            beforeChange(); record.status = status; expanded = false
                        } label: {
                            VStack(spacing: 4) { Image(systemName: status.icon); Text(status.label).font(.system(size: 9, weight: .semibold)) }
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(record.status == status ? tint : Color.gray.opacity(0.08))
                                .foregroundStyle(record.status == status ? .white : AppTheme.ink).clipShape(RoundedRectangle(cornerRadius: 11))
                        }
                    }
                }
                Button { showNote.toggle() } label: { Label(record.notes.isEmpty ? "Add note" : "Edit note", systemImage: "note.text").font(.caption.weight(.semibold)) }.frame(maxWidth: .infinity, alignment: .leading)
                if showNote { TextField("Attendance note", text: $record.notes, axis: .vertical).textFieldStyle(.roundedBorder) }
                if record.status == .late {
                    DatePicker("Arrival", selection: Binding(get: { record.lateArrival ?? .now }, set: { record.lateArrival = $0 }), displayedComponents: .hourAndMinute).font(.subheadline)
                }
            }
        }.cardStyle()
    }
}

private struct StudentPicker: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @Environment(\.dismiss) private var dismiss
    let course: ClassCourse
    let session: ClassSession
    let rosterIDs: Set<UUID>
    let onAdd: ([Student]) -> Void
    @State private var search = ""
    @State private var grade = "All"
    @State private var selected: Set<UUID> = []
    var grades: [String] { ["All"] + Array(Set(repo.students.map(\.grade))).sorted() }
    var visible: [Student] {
        repo.students.filter { $0.active && (search.isEmpty || $0.fullName.localizedCaseInsensitiveContains(search)) && (grade == "All" || $0.grade == grade) }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(grades, id: \.self) { item in Button(item) { grade = item }.buttonStyle(.borderedProminent).tint(grade == item ? AppTheme.deep : .gray.opacity(0.25)) } }.padding(.horizontal)
                }
                if course.isMakeupClass {
                    Label("Searching all students · session-only", systemImage: "arrow.triangle.2.circlepath").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.deep)
                }
                List(visible) { student in
                    Button {
                        guard !rosterIDs.contains(student.id) else { return }
                        if selected.contains(student.id) { selected.remove(student.id) } else { selected.insert(student.id) }
                    } label: {
                        HStack {
                            AvatarView(student: student, size: 42)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(student.fullName).font(.headline).foregroundStyle(AppTheme.ink)
                                Text(studentDetail(student)).font(.caption).foregroundStyle(AppTheme.muted).lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: rosterIDs.contains(student.id) ? "checkmark.circle.fill" : (selected.contains(student.id) ? "checkmark.square.fill" : "square"))
                                .foregroundStyle(rosterIDs.contains(student.id) ? .gray : AppTheme.deep).font(.title3)
                        }
                    }.disabled(rosterIDs.contains(student.id))
                }.listStyle(.plain)
            }.navigationTitle(course.isMakeupClass ? "Makeup students" : "Add to class").searchable(text: $search)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add \(selected.count)") { onAdd(repo.students.filter { selected.contains($0.id) }); dismiss() }.disabled(selected.isEmpty)
                    }
                }
        }
    }
    private func studentDetail(_ student: Student) -> String {
        let classNames = repo.classes.filter { course in repo.enrollments.contains { $0.studentID == student.id && $0.classID == course.id } }.map(\.displayName).joined(separator: ", ")
        if course.isMakeupClass, let credit = repo.makeupCredits.first(where: { $0.studentID == student.id }) {
            let source = repo.classes.first { $0.id == credit.sourceClassID }?.displayName ?? "Archived Class"
            let expiry = credit.expiresOn.map { " · expires \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
            return "\(credit.state.label) credit · missed \(source)\(expiry)"
        }
        return classNames.isEmpty ? "Grade \(student.grade) · No classes yet" : "Grade \(student.grade) · \(classNames)"
    }
}
