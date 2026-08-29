import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }.tabItem { Label("Home", systemImage: "house.fill") }
            NavigationStack { CalendarView() }.tabItem { Label("Calendar", systemImage: "calendar") }
            NavigationStack { StudentDirectoryView() }.tabItem { Label("Students", systemImage: "person.2.fill") }
            NavigationStack { ReportsView() }.tabItem { Label("Reports", systemImage: "chart.bar.fill") }
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @State private var showAddClass = false
    private func nextClass(at now: Date) -> ClassCourse? {
        ScheduleLogic.nextClass(from: repo.classes, at: now)
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            dashboard(at: context.date)
        }
    }

    private func dashboard(at now: Date) -> some View {
        let weekday = Weekday(rawValue: Calendar.current.component(.weekday, from: now))
        let todayClasses = repo.classes.filter { $0.weekday == weekday }.sorted { $0.startMinutes < $1.startMinutes }
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased()).font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(AppTheme.accent)
                        Text("Good afternoon").font(.system(size: 34, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    Image(systemName: "bell").font(.title3).frame(width: 44, height: 44).background(.white).clipShape(Circle())
                }
                if let course = nextClass(at: now) {
                    VStack(alignment: .leading, spacing: 17) {
                        HStack {
                            Label("UP NEXT", systemImage: "sparkles").font(.caption.weight(.bold)).tracking(1)
                            Spacer()
                            Text(course.weekday.name).font(.caption.weight(.semibold))
                        }.foregroundStyle(.white.opacity(0.8))
                        Text(course.displayName).font(.system(size: 34, weight: .bold, design: .rounded))
                        HStack {
                            Label(course.timeLabel, systemImage: "clock")
                            if !course.location.isEmpty {
                                Label(course.location, systemImage: "mappin.and.ellipse")
                            }
                        }.font(.subheadline)
                        Text("\(repo.students(in: course.id).count) students").font(.subheadline.weight(.semibold))
                        NavigationLink {
                            ClassRosterView(course: course)
                        } label: {
                            Label("Take Attendance", systemImage: "checkmark.circle.fill")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                                .background(.white).foregroundStyle(course.color.color).clipShape(RoundedRectangle(cornerRadius: 17))
                        }
                    }.padding(22).foregroundStyle(.white).background(course.color.color.gradient).clipShape(RoundedRectangle(cornerRadius: 30))
                } else {
                    EmptyStateView(
                        icon: "checkmark.circle",
                        title: "Nothing else is in store.",
                        message: "You’re all done for today.",
                        actionTitle: repo.classes.isEmpty ? "Create a class" : nil
                    ) { showAddClass = true }
                }
                if !todayClasses.isEmpty {
                    HStack {
                        Text("Today’s classes").font(.title2.bold())
                        Spacer()
                        NavigationLink("See calendar") { CalendarView() }.font(.subheadline.weight(.semibold))
                    }
                    VStack(spacing: 10) {
                        ForEach(todayClasses) { course in
                            NavigationLink { ClassRosterView(course: course) } label: {
                                HStack(spacing: 14) {
                                    RoundedRectangle(cornerRadius: 4).fill(course.color.color).frame(width: 5, height: 48)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(course.displayName).font(.headline)
                                        Text(course.location.isEmpty ? course.timeLabel : "\(course.timeLabel) · \(course.location)")
                                            .font(.caption).foregroundStyle(AppTheme.muted)
                                    }
                                    Spacer()
                                    Text("\(repo.students(in: course.id).count)").font(.headline).foregroundStyle(AppTheme.ink)
                                    Image(systemName: "chevron.right").foregroundStyle(.gray)
                                }.foregroundStyle(AppTheme.ink).cardStyle()
                            }
                        }
                    }
                }
                if !repo.sessions.isEmpty || !repo.makeupCredits.isEmpty {
                    HStack(spacing: 12) {
                        DashboardMiniCard(icon: "exclamationmark.circle.fill", value: "\(repo.sessions.filter { !$0.isComplete }.count)", label: "Incomplete", color: .orange)
                        DashboardMiniCard(icon: "arrow.triangle.2.circlepath", value: "\(repo.makeupCredits.filter { $0.state == .owed || $0.state == .scheduled }.count)", label: "Makeups due", color: AppTheme.deep)
                    }
                }
            }.padding(20)
        }.background(AppTheme.background).toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAddClass) { AddClassSheet() }
    }
}

private struct DashboardMiniCard: View {
    let icon: String; let value: String; let label: String; let color: Color
    var body: some View {
        HStack { Image(systemName: icon).foregroundStyle(color); VStack(alignment: .leading) { Text(value).font(.title2.bold()); Text(label).font(.caption).foregroundStyle(AppTheme.muted) } }
            .frame(maxWidth: .infinity, alignment: .leading).cardStyle()
    }
}

struct StudentDirectoryView: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @State private var search = ""; @State private var showAdd = false
    var body: some View {
        ScrollView {
            if repo.students.isEmpty {
                EmptyStateView(
                    icon: "person.badge.plus",
                    title: "No students yet.",
                    message: "Your student database is empty. Add someone to get started.",
                    actionTitle: "Create a student"
                ) { showAdd = true }
                .padding(20)
            } else {
            LazyVStack(spacing: 10) {
                ForEach(repo.students.filter { search.isEmpty || $0.fullName.localizedCaseInsensitiveContains(search) }) { student in
                    NavigationLink { StudentProfileView(studentID: student.id) } label: { VStack(spacing: 12) {
                        HStack { AvatarView(student: student); VStack(alignment: .leading) { Text(student.fullName).font(.headline); Text(student.active ? student.gradeLabel : "\(student.gradeLabel) · Inactive").font(.subheadline).foregroundStyle(AppTheme.muted) }; Spacer() }
                        let assigned = repo.classes.filter { course in repo.enrollments.contains { $0.studentID == student.id && $0.classID == course.id } }
                        if !assigned.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack { ForEach(assigned) { Text($0.displayName).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 6).background($0.color.color.opacity(0.15)).foregroundStyle($0.color.color).clipShape(Capsule()) } }
                            }
                        }
                    }.foregroundStyle(AppTheme.ink).cardStyle() }
                }
            }.padding(16)
            }
        }.background(AppTheme.background).navigationTitle("Students").searchable(text: $search)
            .toolbar { Button { showAdd = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $showAdd) { AddStudentSheet() }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
#if DEBUG
    @State private var showResetConfirmation = false
#endif
    var body: some View {
#if DEBUG
        settingsList
            .alert("Reset all app data?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { repo.resetAllData() }
            } message: {
                Text("This permanently removes all local test data and returns to first-time setup.")
            }
#else
        settingsList
#endif
    }

    private var settingsList: some View {
        List {
            Section("Prototype") {
                Button("Show onboarding again") { repo.setupComplete = false }
                LabeledContent("Data source", value: "On-device storage")
            }
            Section("Coming later") {
                Label("Account & authentication", systemImage: "person.crop.circle.badge.clock")
                Label("Supabase sync", systemImage: "externaldrive.badge.icloud")
                Label("Google Calendar", systemImage: "calendar.badge.clock")
            }
#if DEBUG
            Section {
                Button("Reset all app data", role: .destructive) {
                    showResetConfirmation = true
                }
            } header: {
                Text("Development")
            } footer: {
                Text("Deletes all local classes, students, attendance, assignments, and setup progress.")
            }
#endif
        }
        .navigationTitle("Settings")
    }
}
