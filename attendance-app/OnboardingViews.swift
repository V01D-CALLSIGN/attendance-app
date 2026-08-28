import SwiftUI

struct OnboardingFlow: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @State private var step = 1
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                if step > 1 {
                    HStack {
                        Button { withAnimation { step -= 1 } } label: {
                            Image(systemName: "chevron.left").frame(width: 42, height: 42).background(.white).clipShape(Circle())
                        }
                        Spacer()
                        Text("\(step) of 4").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.muted)
                    }.padding(.horizontal, 20).padding(.top, 8)
                }
                Group {
                    switch step {
                    case 1: ClassesSetupStep { withAnimation { step = 2 } }
                    case 2: StudentsSetupStep { withAnimation { step = 3 } }
                    case 3: AssignmentSetupStep { withAnimation { step = 4 } }
                    default: ReviewSetupStep { repo.setupComplete = true }
                    }
                }.transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
    }
}

private struct StepHeader: View {
    let eyebrow: String; let title: String; let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased()).font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(AppTheme.accent)
            Text(title).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(AppTheme.ink)
            Text(subtitle).foregroundStyle(AppTheme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ClassesSetupStep: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @State private var showAdd = false
    let next: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            StepHeader(eyebrow: "First, your week", title: "When are your classes?", subtitle: "Build your teaching rhythm. You can edit it anytime.")
                .padding(.horizontal, 24).padding(.top, 22)
            if repo.classes.isEmpty {
                EmptyStateView(
                    icon: "calendar.badge.plus",
                    title: "No classes yet",
                    message: "Add your first class to start building your weekly schedule.",
                    actionTitle: "Add your first class"
                ) { showAdd = true }
                .padding(.horizontal, 20)
            } else {
                WeeklyScheduleView(classes: repo.classes)
            }
            Button { showAdd = true } label: { Label("Add another class", systemImage: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.large).padding(.horizontal, 24)
            Button("Continue", action: next).buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 24).padding(.bottom, 12)
        }.sheet(isPresented: $showAdd) { AddClassSheet() }
    }
}

struct WeeklyScheduleView: View {
    let classes: [ClassCourse]
    private let days: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                ForEach(days) { day in
                    VStack(spacing: 4) {
                        Text(day.short.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(AppTheme.muted)
                        Text("\(day.rawValue + 6)").font(.headline)
                    }.frame(maxWidth: .infinity)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(days) { day in
                        VStack(spacing: 9) {
                            ForEach(classes.filter { $0.weekday == day }) { course in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(course.name).font(.caption.weight(.bold)).lineLimit(2)
                                    Text(course.timeLabel.replacingOccurrences(of: " PM", with: "")).font(.caption2)
                                }.foregroundStyle(.white).padding(10).frame(width: 104, alignment: .leading)
                                    .background(course.color.color).clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            if classes.allSatisfy({ $0.weekday != day }) {
                                RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5])).foregroundStyle(.gray.opacity(0.25)).frame(width: 104, height: 75)
                            }
                        }
                    }
                }.padding(.horizontal, 24)
            }
            Text("4 PM  ·  ·  ·  5 PM  ·  ·  ·  6 PM").font(.caption2.weight(.medium)).foregroundStyle(AppTheme.muted)
        }.padding(.vertical, 16).background(.white).clipShape(RoundedRectangle(cornerRadius: 26)).padding(.horizontal, 16)
    }
}

struct AddClassSheet: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var day: Weekday = .monday
    @State private var start: Date
    @State private var end: Date
    @State private var color: ClassColor = .blue

    init() {
        let roundedStart = Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(minute: Calendar.current.component(.minute, from: .now) < 30 ? 30 : 0),
            matchingPolicy: .nextTime
        ) ?? .now
        _start = State(initialValue: roundedStart)
        _end = State(initialValue: roundedStart.addingTimeInterval(60 * 60))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Class details") {
                    TextField("Class name", text: $name)
                    Picker("Day", selection: $day) { ForEach(Weekday.allCases) { Text($0.name).tag($0) } }
                    TimeWheelField(title: "Starts", selection: $start)
                    TimeWheelField(title: "Ends", selection: $end)
                }
                Section("Color") {
                    HStack {
                        ForEach(ClassColor.allCases) { option in
                            Circle().fill(option.color).frame(width: 34, height: 34)
                                .overlay(Image(systemName: "checkmark").foregroundStyle(.white).opacity(color == option ? 1 : 0))
                                .onTapGesture { color = option }
                        }
                    }
                }
            }
            .onChange(of: start) { _, newStart in
                end = newStart.addingTimeInterval(60 * 60)
            }
            .navigationTitle("New class").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let cal = Calendar.current
                        let s = cal.component(.hour, from: start) * 60 + cal.component(.minute, from: start)
                        let e = cal.component(.hour, from: end) * 60 + cal.component(.minute, from: end)
                        repo.addClass(ClassCourse(name: name, weekday: day, startMinutes: s, endMinutes: max(e, s + 30), location: "", color: color))
                        dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

private struct TimeWheelField: View {
    let title: String
    @Binding var selection: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            HalfHourTimePicker(selection: $selection)
                .frame(height: 115)
        }
        .padding(.vertical, 4)
    }
}

private struct HalfHourTimePicker: UIViewRepresentable {
    @Binding var selection: Date

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = 30
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.parent = self
        if picker.date != selection {
            picker.setDate(selection, animated: false)
        }
    }

    final class Coordinator: NSObject {
        var parent: HalfHourTimePicker

        init(parent: HalfHourTimePicker) {
            self.parent = parent
        }

        @objc func changed(_ picker: UIDatePicker) {
            parent.selection = picker.date
        }
    }
}

private struct StudentsSetupStep: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @State private var showAdd = false; @State private var search = ""
    let next: () -> Void
    var filtered: [Student] { repo.students.filter { search.isEmpty || $0.fullName.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(spacing: 14) {
            StepHeader(eyebrow: "Next, your people", title: "Who are your students?", subtitle: "Add each student once. They can belong to several classes.")
                .padding(.horizontal, 24).padding(.top, 22)
            TextField("Search students", text: $search).textFieldStyle(.roundedBorder).padding(.horizontal, 24)
            ScrollView {
                if filtered.isEmpty {
                    EmptyStateView(
                        icon: "person.badge.plus",
                        title: search.isEmpty ? "No students yet" : "No students found",
                        message: search.isEmpty ? "Add your first student to create your directory." : "Try another name.",
                        actionTitle: search.isEmpty ? "Add your first student" : nil
                    ) { showAdd = true }
                    .padding(.horizontal, 20)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { student in
                            HStack { AvatarView(student: student); VStack(alignment: .leading) { Text(student.fullName).font(.headline); Text("Grade \(student.grade)").font(.subheadline).foregroundStyle(AppTheme.muted) }; Spacer(); Image(systemName: "ellipsis") }.cardStyle()
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            Button { showAdd = true } label: { Label("Add a student", systemImage: "person.badge.plus").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.large).padding(.horizontal, 24)
            Button("Continue", action: next).buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 24).padding(.bottom, 12)
        }.sheet(isPresented: $showAdd) { AddStudentSheet() }
    }
}

struct AddStudentSheet: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @Environment(\.dismiss) private var dismiss
    @State private var first = ""; @State private var last = ""; @State private var grade = ""; @State private var contact = ""; @State private var notes = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Student") { TextField("First name", text: $first); TextField("Last name", text: $last); TextField("Grade", text: $grade) }
                Section("Optional") { TextField("Parent or student contact", text: $contact); TextField("Notes", text: $notes, axis: .vertical) }
            }.navigationTitle("New student").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { repo.addStudent(Student(firstName: first, lastName: last, grade: grade, contact: contact, notes: notes)); dismiss() }.disabled(first.isEmpty || last.isEmpty) }
            }
        }
    }
}

private struct AssignmentSetupStep: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @State private var selectedClass: UUID?; @State private var search = ""
    @State private var showAddClass = false
    @State private var showAddStudent = false
    let next: () -> Void
    private var activeClass: ClassCourse? { repo.classes.first { $0.id == selectedClass } ?? repo.classes.first }
    var body: some View {
        VStack(spacing: 14) {
            StepHeader(eyebrow: "Make the match", title: "Assign everyone a class.", subtitle: "Tap to add or remove. Students stay visible for multiple classes.")
                .padding(.horizontal, 24).padding(.top, 22)
            if repo.classes.isEmpty || repo.students.isEmpty {
                VStack(spacing: 12) {
                    if repo.classes.isEmpty {
                        EmptyStateView(icon: "calendar.badge.plus", title: "Add a class to assign", message: "Assignments connect students to their recurring classes.", actionTitle: "Add a class") { showAddClass = true }
                    }
                    if repo.students.isEmpty {
                        EmptyStateView(icon: "person.badge.plus", title: "Add a student to assign", message: "Students can be assigned to one or many classes.", actionTitle: "Add a student") { showAddStudent = true }
                    }
                }.padding(.horizontal, 20)
            } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(repo.classes) { course in
                        let count = repo.enrollments.filter { $0.classID == course.id }.count
                        Button { selectedClass = course.id } label: {
                            VStack(alignment: .leading) { Text(course.name).font(.headline); Text("\(count) assigned").font(.caption) }
                                .foregroundStyle((activeClass?.id == course.id) ? .white : AppTheme.ink).padding(14)
                                .background((activeClass?.id == course.id) ? course.color.color : .white).clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }.padding(.horizontal, 20)
            }
            TextField("Search students", text: $search).textFieldStyle(.roundedBorder).padding(.horizontal, 24)
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(repo.students.filter { search.isEmpty || $0.fullName.localizedCaseInsensitiveContains(search) }) { student in
                        let assigned = activeClass.map { course in repo.enrollments.contains { $0.studentID == student.id && $0.classID == course.id } } ?? false
                        Button {
                            guard let id = activeClass?.id else { return }
                            repo.setEnrollment(studentID: student.id, classID: id, assigned: !assigned)
                        } label: {
                            HStack { AvatarView(student: student, size: 42); VStack(alignment: .leading) { Text(student.fullName).font(.headline); Text("Grade \(student.grade)").font(.caption).foregroundStyle(AppTheme.muted) }; Spacer(); Image(systemName: assigned ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(assigned ? (activeClass?.color.color ?? AppTheme.deep) : .gray.opacity(0.35)) }
                                .foregroundStyle(AppTheme.ink).cardStyle()
                        }
                    }
                }.padding(.horizontal, 16)
            }
            }
            Button("Review setup", action: next).buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 24).padding(.bottom, 12)
        }
        .onAppear { selectedClass = selectedClass ?? repo.classes.first?.id }
        .onChange(of: repo.classes.count) { _, _ in selectedClass = selectedClass ?? repo.classes.first?.id }
        .sheet(isPresented: $showAddClass) { AddClassSheet() }
        .sheet(isPresented: $showAddStudent) { AddStudentSheet() }
    }
}

private struct ReviewSetupStep: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    let finish: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 70)).foregroundStyle(AppTheme.accent)
            StepHeader(eyebrow: "Ready to teach", title: "Your week is all set.", subtitle: "Everything stays editable after setup.")
            HStack(spacing: 12) {
                ReviewStat(value: repo.classes.count, label: "Classes")
                ReviewStat(value: repo.students.count, label: "Students")
                ReviewStat(value: repo.enrollments.count, label: "Assignments")
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("WHAT HAPPENS NEXT").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(AppTheme.muted)
                Label("Home opens to your next class", systemImage: "sparkles")
                Label("Attendance takes one tap per student", systemImage: "checkmark.circle")
                Label("Add students from any roster", systemImage: "person.badge.plus")
            }.cardStyle()
            Spacer()
            Button("Finish setup", action: finish).buttonStyle(PrimaryButtonStyle())
        }.padding(24)
    }
}

private struct ReviewStat: View {
    let value: Int; let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) { Text("\(value)").font(.system(size: 30, weight: .bold, design: .rounded)); Text(label).font(.caption).foregroundStyle(AppTheme.muted) }
            .frame(maxWidth: .infinity, alignment: .leading).cardStyle()
    }
}
