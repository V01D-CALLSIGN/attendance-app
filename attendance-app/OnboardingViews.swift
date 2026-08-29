import SwiftUI

struct OnboardingFlow: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @State private var step = 1

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            if !repo.onboardingStarted {
                WelcomeView {
                    withAnimation { repo.onboardingStarted = true }
                }
            } else {
                VStack(spacing: 0) {
                    if step > 1 {
                        HStack {
                            Button { withAnimation { step -= 1 } } label: {
                                Image(systemName: "chevron.left")
                                    .frame(width: 42, height: 42)
                                    .background(.white)
                                    .clipShape(Circle())
                            }
                            Spacer()
                            Text("\(step) of 4")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.muted)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    Group {
                        switch step {
                        case 1: GuidedClassesSetupView { withAnimation { step = 2 } }
                        case 2: StudentsSetupStep { withAnimation { step = 3 } }
                        case 3: AssignmentSetupStep { withAnimation { step = 4 } }
                        default: ReviewSetupStep { repo.setupComplete = true }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
        }
    }
}

private struct WelcomeView: View {
    let begin: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 82))
                .foregroundStyle(AppTheme.deep)
            Text("Welcome")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            Text("Let’s build your teaching week, add your students, and get attendance ready.")
                .font(.title3)
                .foregroundStyle(AppTheme.muted)
                .lineSpacing(5)
            Spacer()
            Button("Let’s begin", action: begin)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
    }
}

struct StepHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            Text(subtitle).foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ClassSetupPhase {
    case type, time, confirm, more, review
}

private struct GuidedClassesSetupView: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @State private var dayIndex = 0
    @State private var phase: ClassSetupPhase = .type
    @State private var selectedType: ClassType?
    @State private var start: Date
    @State private var end: Date
    @State private var editingCourse: ClassCourse?
    let next: () -> Void

    init(next: @escaping () -> Void) {
        self.next = next
        let rounded = Self.roundedStart()
        _start = State(initialValue: rounded)
        _end = State(initialValue: rounded.addingTimeInterval(3600))
    }

    private var day: Weekday { Weekday.mondayFirst[dayIndex] }
    private var isValidTime: Bool { minutes(end) > minutes(start) }

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(
                eyebrow: phase == .review ? "Your week" : "Day \(dayIndex + 1) of 7",
                title: phase == .review ? "Review your classes." : "Let’s make our classes.",
                subtitle: phase == .review ? "Edit or remove anything before adding students." : day.name
            )
            .padding(.horizontal, 24)
            .padding(.top, 22)

            Group {
                switch phase {
                case .type: typeStep
                case .time: timeStep
                case .confirm: confirmationStep
                case .more: moreStep
                case .review: weeklyReview
                }
            }
            .frame(maxHeight: .infinity)
        }
        .sheet(item: $editingCourse) { course in
            EditClassSheet(course: course)
        }
    }

    private var typeStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("What class do you have on \(day.name)?")
                .font(.title2.bold())
            Picker("Class", selection: $selectedType) {
                Text("Select class").tag(nil as ClassType?)
                ForEach(ClassType.allCases) { type in
                    Text(type.rawValue).tag(Optional(type))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            Spacer()
            Button("Done") { withAnimation { phase = .time } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedType == nil)
            Button("No classes on \(day.name)") { advanceDay() }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .padding(24)
    }

    private var timeStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("When is \(selectedType?.rawValue ?? "this class")?")
                    .font(.title2.bold())
                TimeWheelField(title: "Start time", selection: $start)
                    .cardStyle()
                TimeWheelField(title: "End time", selection: $end)
                    .cardStyle()
                if !isValidTime {
                    Label("End time must be later than start time.", systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
                Button("Done") { withAnimation { phase = .confirm } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!isValidTime)
                Button("Back") { withAnimation { phase = .type } }
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .onChange(of: start) { _, newStart in
            end = newStart.addingTimeInterval(3600)
        }
    }

    private var confirmationStep: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("Looks good?")
                .font(.system(size: 38, weight: .bold, design: .rounded))
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("Day", value: day.name)
                LabeledContent("Class", value: selectedType?.rawValue ?? "")
                LabeledContent("Start time", value: timeText(start))
                LabeledContent("End time", value: timeText(end))
            }
            .cardStyle()
            Spacer()
            Button("Yes, continue") { savePendingClass() }
                .buttonStyle(PrimaryButtonStyle())
            Button("Go back and edit") { withAnimation { phase = .time } }
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    private var moreStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 68))
                .foregroundStyle(AppTheme.deep)
            Text("Are there more classes for \(day.name)?")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Spacer()
            Button("Yes") { resetDraftForSameDay() }
                .buttonStyle(PrimaryButtonStyle())
            Button("No") { advanceDay() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    private var weeklyReview: some View {
        VStack(spacing: 14) {
            if repo.classes.isEmpty {
                EmptyStateView(
                    icon: "calendar",
                    title: "No classes this week",
                    message: "You can continue and add classes later."
                )
                .padding(.horizontal, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(repo.classes.sorted(by: classSort)) { course in
                            HStack(spacing: 14) {
                                Circle().fill(course.color.color).frame(width: 12)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(course.displayName).font(.headline)
                                    Text(course.timeLabel).font(.subheadline).foregroundStyle(AppTheme.muted)
                                }
                                Spacer()
                                Button { editingCourse = course } label: { Image(systemName: "pencil") }
                                Button(role: .destructive) { repo.removeClass(id: course.id) } label: { Image(systemName: "trash") }
                            }
                            .cardStyle()
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            Button("Continue to students", action: next)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
    }

    private func savePendingClass() {
        guard let selectedType else { return }
        let palette: ClassColor = selectedType == .art ? .coral : .blue
        repo.addClass(ClassCourse(
            name: selectedType.rawValue,
            weekday: day,
            startMinutes: minutes(start),
            endMinutes: minutes(end),
            location: "",
            color: palette
        ))
        withAnimation { phase = .more }
    }

    private func resetDraftForSameDay() {
        selectedType = nil
        let rounded = Self.roundedStart()
        start = rounded
        end = rounded.addingTimeInterval(3600)
        withAnimation { phase = .type }
    }

    private func advanceDay() {
        if dayIndex == Weekday.mondayFirst.count - 1 {
            withAnimation { phase = .review }
        } else {
            dayIndex += 1
            resetDraftForSameDay()
        }
    }

    private func minutes(_ date: Date) -> Int {
        Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func classSort(_ lhs: ClassCourse, _ rhs: ClassCourse) -> Bool {
        let leftDay = Weekday.mondayFirst.firstIndex(of: lhs.weekday) ?? 0
        let rightDay = Weekday.mondayFirst.firstIndex(of: rhs.weekday) ?? 0
        return leftDay == rightDay ? lhs.startMinutes < rhs.startMinutes : leftDay < rightDay
    }

    static func roundedStart(now: Date = .now) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let minute = components.minute ?? 0
        if minute == 0 || minute == 30 {
            return calendar.date(from: components) ?? now
        }
        if minute < 30 {
            components.minute = 30
            return calendar.date(from: components) ?? now
        }
        components.minute = 0
        let hourStart = calendar.date(from: components) ?? now
        return calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? now
    }
}

struct WeeklyScheduleView: View {
    let classes: [ClassCourse]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Weekday.mondayFirst) { day in
                    VStack(spacing: 9) {
                        Text(day.short.uppercased())
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.muted)
                        ForEach(classes.filter { $0.weekday == day }.sorted { $0.startMinutes < $1.startMinutes }) { course in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(course.displayName).font(.caption.weight(.bold)).lineLimit(2)
                                Text(course.timeLabel).font(.caption2)
                            }
                            .foregroundStyle(.white)
                            .padding(10)
                            .frame(width: 120, alignment: .leading)
                            .background(course.color.color)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .frame(width: 120)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }
}

struct AddClassSheet: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @Environment(\.dismiss) private var dismiss
    @State private var type: ClassType?
    @State private var day: Weekday = .monday
    @State private var start: Date
    @State private var end: Date

    init() {
        let rounded = GuidedClassesSetupView.roundedStart()
        _start = State(initialValue: rounded)
        _end = State(initialValue: rounded.addingTimeInterval(3600))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Class details") {
                    Picker("Class", selection: $type) {
                        Text("Select class").tag(nil as ClassType?)
                        ForEach(ClassType.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Picker("Day", selection: $day) {
                        ForEach(Weekday.mondayFirst) { Text($0.name).tag($0) }
                    }
                    TimeWheelField(title: "Starts", selection: $start)
                    TimeWheelField(title: "Ends", selection: $end)
                    if !validTime {
                        Text("End time must be later than start time.").foregroundStyle(.red)
                    }
                }
            }
            .onChange(of: start) { _, value in end = value.addingTimeInterval(3600) }
            .navigationTitle("New class")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let type else { return }
                        repo.addClass(ClassCourse(
                            name: type.rawValue,
                            weekday: day,
                            startMinutes: minutes(start),
                            endMinutes: minutes(end),
                            location: "",
                            color: type == .art ? .coral : .blue
                        ))
                        dismiss()
                    }
                    .disabled(type == nil || !validTime)
                }
            }
        }
    }

    private var validTime: Bool { minutes(end) > minutes(start) }
    private func minutes(_ date: Date) -> Int {
        Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
    }
}

private struct EditClassSheet: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @Environment(\.dismiss) private var dismiss
    let course: ClassCourse
    @State private var type: ClassType?
    @State private var start: Date
    @State private var end: Date

    init(course: ClassCourse) {
        self.course = course
        _type = State(initialValue: ClassType(rawValue: course.name))
        _start = State(initialValue: Self.date(minutes: course.startMinutes))
        _end = State(initialValue: Self.date(minutes: course.endMinutes))
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Class", selection: $type) {
                    Text("Select class").tag(nil as ClassType?)
                    ForEach(ClassType.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }
                TimeWheelField(title: "Start time", selection: $start)
                TimeWheelField(title: "End time", selection: $end)
                if !validTime { Text("End time must be later than start time.").foregroundStyle(.red) }
            }
            .navigationTitle("Edit \(course.weekday.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let type else { return }
                        var updated = course
                        updated.name = type.rawValue
                        updated.startMinutes = minutes(start)
                        updated.endMinutes = minutes(end)
                        updated.color = type == .art ? .coral : .blue
                        repo.updateClass(updated)
                        dismiss()
                    }
                    .disabled(type == nil || !validTime)
                }
            }
        }
    }

    private var validTime: Bool { minutes(end) > minutes(start) }
    private func minutes(_ date: Date) -> Int {
        Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
    }
    private static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }
}

struct TimeWheelField: View {
    let title: String
    @Binding var selection: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            HalfHourTimePicker(selection: $selection).frame(height: 115)
        }
        .padding(.vertical, 4)
    }
}

private struct HalfHourTimePicker: UIViewRepresentable {
    @Binding var selection: Date
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
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
        if picker.date != selection { picker.setDate(selection, animated: false) }
    }
    final class Coordinator: NSObject {
        var parent: HalfHourTimePicker
        init(parent: HalfHourTimePicker) { self.parent = parent }
        @objc func changed(_ picker: UIDatePicker) { parent.selection = picker.date }
    }
}

private struct StudentsSetupStep: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @State private var showAdd = false
    @State private var search = ""
    let next: () -> Void
    private var filtered: [Student] {
        repo.students.filter { search.isEmpty || $0.fullName.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(spacing: 14) {
            StepHeader(eyebrow: "Next, your people", title: "Who are your students?", subtitle: "Add each student once. They can belong to several classes.")
                .padding(.horizontal, 24).padding(.top, 22)
            TextField("Search students", text: $search).textFieldStyle(.roundedBorder).padding(.horizontal, 24)
            ScrollView {
                if filtered.isEmpty {
                    EmptyStateView(icon: "person.badge.plus", title: search.isEmpty ? "No students yet" : "No students found", message: search.isEmpty ? "Add your first student to create your directory." : "Try another name.", actionTitle: search.isEmpty ? "Add your first student" : nil) { showAdd = true }
                        .padding(.horizontal, 20)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { student in
                            HStack {
                                AvatarView(student: student)
                                VStack(alignment: .leading) {
                                    Text(student.fullName).font(.headline)
                                    Text(student.gradeLabel).font(.subheadline).foregroundStyle(AppTheme.muted)
                                }
                                Spacer()
                            }
                            .cardStyle()
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            Button { showAdd = true } label: { Label("Add a student", systemImage: "person.badge.plus").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.large).padding(.horizontal, 24)
            Button("Continue", action: next).buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 24).padding(.bottom, 12)
        }
        .sheet(isPresented: $showAdd) { AddStudentSheet() }
    }
}

struct AddStudentSheet: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @Environment(\.dismiss) private var dismiss
    @State private var first = ""
    @State private var last = ""
    @State private var grade: GradeOption?
    @State private var contact = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Student") {
                    TextField("First name", text: $first)
                    TextField("Last name", text: $last)
                    Picker("Grade", selection: $grade) {
                        Text("Select grade").tag(nil as GradeOption?)
                        ForEach(GradeOption.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                }
                Section("Optional") {
                    TextField("Parent or student contact", text: $contact)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("New student")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let grade else { return }
                        repo.addStudent(Student(firstName: first, lastName: last, grade: grade.rawValue, contact: contact, notes: notes))
                        dismiss()
                    }
                    .disabled(first.isEmpty || last.isEmpty || grade == nil)
                }
            }
        }
    }
}

private struct AssignmentSetupStep: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @State private var selectedClass: UUID?
    @State private var search = ""
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
                }
                .padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(repo.classes) { course in
                            let count = repo.enrollments.filter { $0.classID == course.id }.count
                            Button { selectedClass = course.id } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(course.displayName).font(.headline)
                                    Text(course.timeLabel).font(.caption)
                                    Text("\(count) assigned").font(.caption2)
                                }
                                .foregroundStyle(activeClass?.id == course.id ? .white : AppTheme.ink)
                                .padding(14)
                                .background(activeClass?.id == course.id ? course.color.color : .white)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                            }
                            .dropDestination(for: String.self) { identifiers, _ in
                                for identifier in identifiers {
                                    if let studentID = UUID(uuidString: identifier) {
                                        repo.setEnrollment(studentID: studentID, classID: course.id, assigned: true)
                                    }
                                }
                                return !identifiers.isEmpty
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                TextField("Search students", text: $search).textFieldStyle(.roundedBorder).padding(.horizontal, 24)
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(repo.students.filter { search.isEmpty || $0.fullName.localizedCaseInsensitiveContains(search) }) { student in
                            let assigned = activeClass.map { course in
                                repo.enrollments.contains { $0.studentID == student.id && $0.classID == course.id }
                            } ?? false
                            Button {
                                guard let id = activeClass?.id else { return }
                                repo.setEnrollment(studentID: student.id, classID: id, assigned: !assigned)
                            } label: {
                                HStack {
                                    AvatarView(student: student, size: 42)
                                    VStack(alignment: .leading) {
                                        Text(student.fullName).font(.headline)
                                        Text(student.gradeLabel).font(.caption).foregroundStyle(AppTheme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: assigned ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                        .foregroundStyle(assigned ? (activeClass?.color.color ?? AppTheme.deep) : .gray.opacity(0.35))
                                }
                                .foregroundStyle(AppTheme.ink)
                                .cardStyle()
                            }
                            .draggable(student.id.uuidString)
                        }
                    }
                    .padding(.horizontal, 16)
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
            }
            .cardStyle()
            Spacer()
            Button("Finish setup", action: finish).buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
    }
}

private struct ReviewStat: View {
    let value: Int
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(value)").font(.system(size: 30, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
