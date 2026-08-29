import SwiftUI

private struct CalendarSeed: Identifiable {
    let id = UUID()
    let date: Date
    let startMinutes: Int
}

struct CalendarView: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @State private var week = CalendarLogic.startOfWeek(containing: .now)
    @State private var selected: CalendarOccurrence?
    @State private var createSeed: CalendarSeed?
    @State private var pendingSeed: CalendarSeed?
    private let calendar = Calendar.current
    private let dayWidth: CGFloat = 94
    private let timeWidth: CGFloat = 54
    private let slotHeight: CGFloat = 34
    private let headerHeight: CGFloat = 52

    private var days: [Date] { (0..<7).map { calendar.date(byAdding: .day, value: $0, to: week)! } }
    private var occurrences: [CalendarOccurrence] {
        CalendarLogic.occurrences(courses: repo.classes, sessions: repo.sessions, week: week)
    }
    private var placements: [CalendarOccurrencePlacement] { CalendarLogic.placements(for: occurrences) }

    var body: some View {
        VStack(spacing: 0) {
            weekControls
            ScrollViewReader { horizontalProxy in
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        dayHeaders
                        ScrollViewReader { verticalProxy in
                            ScrollView(.vertical) {
                                ZStack(alignment: .topLeading) {
                                    grid
                                    pendingClassBlock
                                    classBlocks
                                    currentTimeIndicator
                                }
                                .frame(width: timeWidth + dayWidth * 7, height: slotHeight * 48)
                            }
                            .onAppear { scrollVertically(verticalProxy) }
                            .onChange(of: week) { _, _ in scrollVertically(verticalProxy) }
                        }
                    }
                    .frame(width: timeWidth + dayWidth * 7)
                }
                .onAppear { scrollHorizontally(horizontalProxy) }
                .onChange(of: week) { _, _ in scrollHorizontally(horizontalProxy) }
            }
            .background(.white)
            .overlay(alignment: .top) {
                if occurrences.isEmpty {
                    Text("No classes scheduled this week. Tap a time to add one.")
                        .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule()).padding(.top, 62)
                }
            }
        }
        .background(AppTheme.background)
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { occurrence in
            NavigationStack { ClassDetailsView(occurrence: occurrence) }
        }
        .sheet(item: $createSeed) { seed in
            NavigationStack { ClassEditorView(seedDate: seed.date, seedStartMinutes: seed.startMinutes) }
        }
    }

    private var dayHeaders: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.white)
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                VStack(spacing: 1) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption.bold())
                    Text(day.formatted(.dateTime.day())).font(.headline)
                }
                .foregroundStyle(calendar.isDateInToday(day) ? .white : AppTheme.ink)
                .frame(width: dayWidth, height: 45)
                .background(calendar.isDateInToday(day) ? AppTheme.accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .position(x: timeWidth + dayWidth * CGFloat(index) + dayWidth / 2, y: headerHeight / 2)
                .id("day-\(index)")
            }
        }
        .frame(height: headerHeight)
    }

    private var weekControls: some View {
        VStack(spacing: 8) {
            HStack {
                Button { moveWeek(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                VStack(spacing: 2) {
                    Text(dateRange).font(.headline)
                    Button("Today") { week = CalendarLogic.startOfWeek(containing: .now) }
                        .font(.caption.weight(.semibold))
                }
                Spacer()
                Button { moveWeek(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.bordered).padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
        .background(AppTheme.background)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 35).onEnded { value in
            if value.translation.width < -35 { moveWeek(1) }
            if value.translation.width > 35 { moveWeek(-1) }
        })
    }

    private var grid: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.white)
            ForEach(0..<24, id: \.self) { hour in
                Text(hourLabel(hour)).font(.caption2).foregroundStyle(AppTheme.muted)
                    .frame(width: timeWidth - 7, alignment: .trailing)
                    .position(x: (timeWidth - 7) / 2, y: CGFloat(hour * 2) * slotHeight + 8)
            }
            ForEach(0..<7, id: \.self) { dayIndex in
                ForEach(0..<48, id: \.self) { slot in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .overlay(Rectangle().stroke(Color.gray.opacity(slot.isMultiple(of: 2) ? 0.17 : 0.08), lineWidth: 0.5))
                        .frame(width: dayWidth, height: slotHeight)
                        .position(
                            x: timeWidth + CGFloat(dayIndex) * dayWidth + dayWidth / 2,
                            y: CGFloat(slot) * slotHeight + slotHeight / 2
                        )
                        .id(dayIndex == 0 ? "slot-\(slot)" : "cell-\(dayIndex)-\(slot)")
                        .onTapGesture {
                            let date = days[dayIndex]
                            beginCreating(on: date, startMinutes: slot * 30)
                        }
                }
            }
        }
    }

    private var classBlocks: some View {
        ForEach(placements) { placement in
            let occurrence = placement.occurrence
            let dayIndex = days.firstIndex(where: { calendar.isDate($0, inSameDayAs: occurrence.date) }) ?? 0
            let duration = max(30, occurrence.endMinutes - occurrence.startMinutes)
            let availableWidth = dayWidth - 6
            let blockWidth = availableWidth / CGFloat(placement.laneCount)
            Button { selected = occurrence } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        Image(systemName: occurrence.course.name == ClassType.art.rawValue ? "paintbrush.fill" : "book.fill")
                        Text(occurrence.course.name).font(.caption.bold()).lineLimit(1)
                        if occurrence.isMakeupClass { Image(systemName: "arrow.triangle.2.circlepath") }
                        if isComplete(occurrence) { Image(systemName: "checkmark.circle.fill") }
                    }.font(.system(size: 10, weight: .bold))
                    Text(shortTime(occurrence.startMinutes)).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    if duration >= 60 { Text("\(repo.students(in: occurrence.course.id).count) students").font(.system(size: 9)).lineLimit(1) }
                }
                .foregroundStyle(.white)
                .padding(5)
                .frame(width: blockWidth - 2, height: max(30, CGFloat(duration) / 30 * slotHeight - 3), alignment: .topLeading)
                .background(occurrence.course.color.color.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: occurrence.course.color.color.opacity(0.2), radius: 3, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(occurrence.displayName), \(occurrence.timeLabel)\(isComplete(occurrence) ? ", attendance complete" : "")")
            .accessibilityHint("Opens class details")
            .position(
                x: timeWidth + CGFloat(dayIndex) * dayWidth + 3 + blockWidth * (CGFloat(placement.lane) + 0.5),
                y: CGFloat(occurrence.startMinutes) / 30 * slotHeight + CGFloat(duration) / 60 * slotHeight
            )
        }
    }

    @ViewBuilder private var pendingClassBlock: some View {
        if let seed = pendingSeed,
           let dayIndex = days.firstIndex(where: { calendar.isDate($0, inSameDayAs: seed.date) }) {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                Text(shortTime(seed.startMinutes)).font(.caption.bold())
            }
            .foregroundStyle(AppTheme.deep)
            .padding(6)
            .frame(width: dayWidth - 6, height: slotHeight * 2 - 3, alignment: .topLeading)
            .background(AppTheme.deep.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.deep, style: StrokeStyle(lineWidth: 1.5, dash: [4])))
            .position(
                x: timeWidth + CGFloat(dayIndex) * dayWidth + dayWidth / 2,
                y: CGFloat(seed.startMinutes) / 30 * slotHeight + slotHeight
            )
            .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder private var currentTimeIndicator: some View {
        if days.contains(where: { calendar.isDateInToday($0) }) {
            let now = Date.now
            let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
            let dayIndex = days.firstIndex(where: { calendar.isDateInToday($0) }) ?? 0
            HStack(spacing: 2) {
                Text("Now").font(.system(size: 8, weight: .bold)).foregroundStyle(.red)
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Rectangle().fill(Color.red).frame(height: 1.5)
            }
            .frame(width: dayWidth)
            .position(
                x: timeWidth + CGFloat(dayIndex) * dayWidth + dayWidth / 2,
                y: CGFloat(minutes) / 30 * slotHeight
            )
        }
    }

    private var dateRange: String {
        let end = calendar.date(byAdding: .day, value: 6, to: week)!
        return "\(week.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day().year()))"
    }
    private func moveWeek(_ amount: Int) { week = calendar.date(byAdding: .weekOfYear, value: amount, to: week)! }
    private func beginCreating(on date: Date, startMinutes: Int) {
        let seed = CalendarSeed(date: date, startMinutes: startMinutes)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.snappy(duration: 0.15)) { pendingSeed = seed }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            createSeed = seed
            pendingSeed = nil
        }
    }
    private func isComplete(_ occurrence: CalendarOccurrence) -> Bool {
        occurrence.session?.isComplete == true || repo.sessions.contains {
            $0.classID == occurrence.course.id && calendar.isDate($0.date, inSameDayAs: occurrence.date) && $0.isComplete
        }
    }
    private func scrollHorizontally(_ proxy: ScrollViewProxy) {
        let today = days.firstIndex(where: { calendar.isDateInToday($0) })
        let target = today ?? occurrences.first.flatMap { occurrence in days.firstIndex { calendar.isDate($0, inSameDayAs: occurrence.date) } } ?? 0
        DispatchQueue.main.async { proxy.scrollTo("day-\(target)", anchor: .center) }
    }
    private func scrollVertically(_ proxy: ScrollViewProxy) {
        let currentMinutes = calendar.component(.hour, from: .now) * 60 + calendar.component(.minute, from: .now)
        let targetMinutes = days.contains(where: { calendar.isDateInToday($0) }) ? currentMinutes : occurrences.first?.startMinutes ?? 8 * 60
        let slot = max(0, min(47, targetMinutes / 30))
        DispatchQueue.main.async { proxy.scrollTo("slot-\(slot)", anchor: .center) }
    }
    private func hourLabel(_ hour: Int) -> String { hour == 0 ? "12 AM" : hour < 12 ? "\(hour) AM" : hour == 12 ? "12 PM" : "\(hour - 12) PM" }
    private func shortTime(_ minutes: Int) -> String { ClassCourse(name: "", weekday: .monday, startMinutes: minutes, endMinutes: minutes + 30, location: "", color: .blue).timeLabel.components(separatedBy: "–")[0] }
}

struct ClassDetailsView: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @Environment(\.dismiss) private var dismiss
    let occurrence: CalendarOccurrence
    @State private var edit = false
    @State private var duplicate = false

    private var current: CalendarOccurrence {
        guard let course = repo.classes.first(where: { $0.id == occurrence.course.id }) else { return occurrence }
        if let sessionID = occurrence.session?.id, let session = repo.sessions.first(where: { $0.id == sessionID }) {
            return CalendarOccurrence(id: session.id.uuidString, course: course, date: session.date, originalDate: session.originalDate ?? session.date, startMinutes: session.startMinutesSnapshot ?? course.startMinutes, endMinutes: session.endMinutesSnapshot ?? course.endMinutes, session: session)
        }
        let week = CalendarLogic.startOfWeek(containing: occurrence.date)
        let offset = course.weekday == .sunday ? 6 : course.weekday.rawValue - Weekday.monday.rawValue
        let updatedDate = Calendar.current.date(byAdding: .day, value: offset, to: week) ?? occurrence.date
        return CalendarOccurrence(id: occurrence.id, course: course, date: updatedDate, originalDate: occurrence.originalDate, startMinutes: course.startMinutes, endMinutes: course.endMinutes, session: nil)
    }
    private var assigned: [Student] { repo.students(in: current.course.id) }
    private var matchingSession: ClassSession? {
        current.session ?? repo.sessions.first { $0.classID == current.course.id && Calendar.current.isDate($0.date, inSameDayAs: current.date) }
    }
    private var attendanceCourse: ClassCourse {
        var course = current.course
        course.weekday = current.weekday; course.startMinutes = current.startMinutes; course.endMinutes = current.endMinutes
        course.location = current.location; course.notes = current.notes; course.isMakeupClass = current.isMakeupClass
        return course
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(current.course.name.uppercased()).font(.caption.bold()).foregroundStyle(current.course.color.color)
                    Text(current.displayName).font(.title2.bold())
                    Label(current.date.formatted(date: .complete, time: .omitted), systemImage: "calendar")
                    Label(current.timeLabel, systemImage: "clock")
                    if !current.location.isEmpty { Label(current.location, systemImage: "mappin") }
                }.padding(.vertical, 6)
            }
            if Calendar.current.isDateInToday(current.date) {
                Section {
                    NavigationLink { ClassRosterView(course: attendanceCourse) } label: {
                        Label("Take Attendance", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(current.course.color.color)
                    }
                }
            }
            Section("Class details") {
                LabeledContent("Day", value: current.weekday.name)
                LabeledContent("Recurrence", value: current.recurrence)
                LabeledContent("Attendance", value: matchingSession?.isComplete == true ? "Completed" : "Not taken")
                LabeledContent("Makeup class", value: current.isMakeupClass ? "Yes" : "No")
                if !current.notes.isEmpty { Text(current.notes) }
            }
            Section("Assigned students · \(assigned.count)") {
                if assigned.isEmpty { Text("No students yet.").foregroundStyle(AppTheme.muted) }
                ForEach(assigned) { student in
                    HStack { AvatarView(student: student, size: 36); Text(student.fullName); Spacer(); Text(student.gradeLabel).foregroundStyle(AppTheme.muted) }
                }
            }
        }
        .navigationTitle("Class details").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { edit = true } label: { Label("Edit Class", systemImage: "pencil") }
                    Button { edit = true } label: { Label("Manage Students", systemImage: "person.badge.plus") }
                    Button { duplicate = true } label: { Label("Duplicate Class", systemImage: "plus.square.on.square") }
                } label: { Label("Actions", systemImage: "ellipsis.circle").fontWeight(.semibold) }
            }
        }
        .sheet(isPresented: $edit) {
            NavigationStack { ClassEditorView(occurrence: current) { returnToCalendar() } }
        }
        .sheet(isPresented: $duplicate) {
            NavigationStack { ClassEditorView(duplicateOf: current) { returnToCalendar() } }
        }
    }

    private func returnToCalendar() { DispatchQueue.main.async { dismiss() } }
}

struct ClassEditorView: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @Environment(\.dismiss) private var dismiss
    private let occurrence: CalendarOccurrence?
    private let initialType: ClassType?
    private let initialDate: Date
    private let initialStart: Int
    private let initialEnd: Int
    private let initialLocation: String
    private let initialRecurrence: String
    private let initialNotes: String
    private let initialMakeup: Bool
    private let initialAssigned: Set<UUID>
    private let onSaved: () -> Void

    @State private var type: ClassType?
    @State private var date: Date
    @State private var start: Date
    @State private var end: Date
    @State private var location: String
    @State private var recurrence: String
    @State private var notes: String
    @State private var isMakeup: Bool
    @State private var assigned: Set<UUID>
    @State private var baselineAssigned: Set<UUID> = []
    @State private var confirmDelete = false
    @State private var showEditScope = false
    @State private var showDeleteScope = false
    @State private var deleteScope: RecurrenceEditScope = .every
    @State private var confirmDiscard = false
    @State private var studentSearch = ""
    @State private var studentGrade = "All"
    @State private var endWasManuallyChanged = false

    init(occurrence: CalendarOccurrence, onSaved: @escaping () -> Void = {}) {
        self.occurrence = occurrence
        self.onSaved = onSaved
        let ids: Set<UUID> = []
        initialType = ClassType(rawValue: occurrence.course.name)
        initialDate = occurrence.date
        initialStart = occurrence.startMinutes
        initialEnd = occurrence.endMinutes
        initialLocation = occurrence.location
        initialRecurrence = occurrence.recurrence
        initialNotes = occurrence.notes
        initialMakeup = occurrence.isMakeupClass
        initialAssigned = ids
        _type = State(initialValue: initialType)
        _date = State(initialValue: occurrence.date)
        _start = State(initialValue: Self.time(occurrence.startMinutes, on: occurrence.date))
        _end = State(initialValue: Self.time(occurrence.endMinutes, on: occurrence.date))
        _location = State(initialValue: occurrence.location)
        _recurrence = State(initialValue: occurrence.recurrence)
        _notes = State(initialValue: occurrence.notes)
        _isMakeup = State(initialValue: occurrence.isMakeupClass)
        _assigned = State(initialValue: ids)
    }

    init(seedDate: Date, seedStartMinutes: Int, onSaved: @escaping () -> Void = {}) {
        occurrence = nil
        self.onSaved = onSaved
        initialType = nil
        initialDate = seedDate
        initialStart = seedStartMinutes
        initialEnd = min(seedStartMinutes + 60, 24 * 60)
        initialLocation = ""
        initialRecurrence = ""
        initialNotes = ""
        initialMakeup = false
        initialAssigned = []
        _type = State(initialValue: nil)
        _date = State(initialValue: seedDate)
        _start = State(initialValue: Self.time(seedStartMinutes, on: seedDate))
        _end = State(initialValue: Self.time(min(seedStartMinutes + 60, 24 * 60 - 30), on: seedDate))
        _location = State(initialValue: "")
        _recurrence = State(initialValue: "")
        _notes = State(initialValue: "")
        _isMakeup = State(initialValue: false)
        _assigned = State(initialValue: [])
    }

    init(duplicateOf source: CalendarOccurrence, onSaved: @escaping () -> Void = {}) {
        occurrence = nil
        self.onSaved = onSaved
        initialType = ClassType(rawValue: source.course.name)
        initialDate = source.date
        initialStart = source.startMinutes
        initialEnd = source.endMinutes
        initialLocation = source.location
        initialRecurrence = source.recurrence
        initialNotes = source.notes
        initialMakeup = source.isMakeupClass
        initialAssigned = []
        _type = State(initialValue: initialType)
        _date = State(initialValue: source.date)
        _start = State(initialValue: Self.time(source.startMinutes, on: source.date))
        _end = State(initialValue: Self.time(source.endMinutes, on: source.date))
        _location = State(initialValue: source.location)
        _recurrence = State(initialValue: source.recurrence)
        _notes = State(initialValue: source.notes)
        _isMakeup = State(initialValue: source.isMakeupClass)
        _assigned = State(initialValue: [])
    }

    var body: some View {
        Form {
            Section("Class") {
                Picker("Class type", selection: $type) {
                    Text("Select class").tag(nil as ClassType?)
                    ForEach(ClassType.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TimeWheelField(title: "Start time", selection: $start)
                TimeWheelField(title: "End time", selection: Binding(get: { end }, set: { end = $0; endWasManuallyChanged = true }))
                if endMinutes <= startMinutes { Text("End time must be later than start time.").foregroundStyle(.red) }
                TextField("Location", text: $location)
            }
            Section("Schedule") {
                Picker("Recurrence", selection: $recurrence) {
                    Text("Select recurrence").tag("")
                    Text("Does not repeat").tag("Does not repeat")
                    Text("Every week").tag("Every week")
                }
                Toggle("Makeup class", isOn: $isMakeup)
                TextField("Notes", text: $notes, axis: .vertical)
            }
            Section("Assigned students") {
                TextField("Search students", text: $studentSearch)
                Picker("Grade", selection: $studentGrade) {
                    Text("All grades").tag("All")
                    ForEach(GradeOption.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                if filteredStudents.isEmpty { Text(repo.students.filter(\.active).isEmpty ? "No students yet." : "No matching students.").foregroundStyle(AppTheme.muted) }
                ForEach(filteredStudents) { student in
                    Toggle(isOn: assignmentBinding(student.id)) {
                        HStack { AvatarView(student: student, size: 34); VStack(alignment: .leading) { Text(student.fullName); Text(student.gradeLabel).font(.caption).foregroundStyle(AppTheme.muted) } }
                    }
                }
            }
            if occurrence != nil {
                Section { Button("Remove class…", role: .destructive) { requestDelete() } }
            }
            if let error = repo.lastError { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(occurrence == nil ? "New class" : "Edit class")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if changed { confirmDiscard = true } else { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { requestSave() }.disabled(!valid || !changed) }
        }
        .onAppear {
            guard let occurrence, assigned.isEmpty else { return }
            let existing = repo.assignedStudentIDs(classID: occurrence.course.id)
            assigned = existing
            baselineAssigned = existing
        }
        .onChange(of: start) { oldValue, newValue in
            guard !endWasManuallyChanged else { return }
            let delta = newValue.timeIntervalSince(oldValue)
            end = end.addingTimeInterval(delta)
        }
        .alert("Delete this class?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { deleteClass(scope: deleteScope) }
        } message: {
            Text("Historical attendance will be retained. This action cannot be undone.")
        }
        .confirmationDialog("Apply changes to", isPresented: $showEditScope, titleVisibility: .visible) {
            ForEach(RecurrenceEditScope.allCases) { choice in Button(choice.rawValue) { save(scope: choice) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Remove which classes?", isPresented: $showDeleteScope, titleVisibility: .visible) {
            ForEach(RecurrenceEditScope.allCases) { choice in Button(choice.rawValue, role: .destructive) { deleteScope = choice; confirmDelete = true } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Discard unsaved changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
    }

    private var startMinutes: Int { Calendar.current.component(.hour, from: start) * 60 + Calendar.current.component(.minute, from: start) }
    private var endMinutes: Int { Calendar.current.component(.hour, from: end) * 60 + Calendar.current.component(.minute, from: end) }
    private var valid: Bool { type != nil && endMinutes > startMinutes && ["Every week", "Does not repeat"].contains(recurrence) }
    private var filteredStudents: [Student] {
        repo.students.filter { student in
            student.active && (studentSearch.isEmpty || student.fullName.localizedCaseInsensitiveContains(studentSearch)) && (studentGrade == "All" || student.grade == studentGrade)
        }
    }
    private var changed: Bool {
        occurrence == nil || type != initialType || !Calendar.current.isDate(date, inSameDayAs: initialDate) || startMinutes != initialStart || endMinutes != initialEnd || location != initialLocation || recurrence != initialRecurrence || notes != initialNotes || isMakeup != initialMakeup || assigned != baselineAssigned
    }
    private func assignmentBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { assigned.contains(id) }, set: { value in if value { assigned.insert(id) } else { assigned.remove(id) } })
    }
    private func requestSave() {
        if occurrence?.course.recurrence == "Every week" { showEditScope = true } else { save(scope: .every) }
    }
    private func save(scope: RecurrenceEditScope) {
        guard let type else { return }
        let weekday = Weekday(rawValue: Calendar.current.component(.weekday, from: date)) ?? .monday
        var course = occurrence?.course ?? ClassCourse(name: type.rawValue, weekday: weekday, startMinutes: startMinutes, endMinutes: endMinutes, startDate: date, location: location, color: type == .art ? .coral : .blue)
        course.name = type.rawValue
        course.weekday = weekday
        course.startMinutes = startMinutes
        course.endMinutes = endMinutes
        course.startDate = Calendar.current.startOfDay(for: date)
        course.location = location
        course.recurrence = recurrence
        course.notes = notes
        course.isMakeupClass = isMakeup
        course.color = type == .art ? .coral : .blue
        let saved: Bool
        if let occurrence {
            saved = repo.saveClassEdit(original: occurrence.course, edited: course, occurrenceDate: occurrence.originalDate, scope: scope, assignedStudentIDs: assigned)
        } else {
            saved = repo.createClass(course, assignedStudentIDs: assigned)
        }
        if saved { withAnimation(.snappy) { onSaved(); dismiss() } }
    }
    private func requestDelete() {
        if occurrence?.course.recurrence == "Every week" { showDeleteScope = true } else { deleteScope = .every; confirmDelete = true }
    }
    private func deleteClass(scope: RecurrenceEditScope) {
        guard let occurrence else { return }
        if repo.deleteClass(occurrence.course, occurrenceDate: occurrence.originalDate, scope: scope) { withAnimation(.snappy) { onSaved(); dismiss() } }
    }
    private static func time(_ minutes: Int, on date: Date) -> Date {
        Calendar.current.date(bySettingHour: min(minutes, 1439) / 60, minute: min(minutes, 1439) % 60, second: 0, of: date) ?? date
    }
}
