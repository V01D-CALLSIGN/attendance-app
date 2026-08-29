import SwiftUI
import PhotosUI

struct StudentProfileView: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    let studentID: UUID
    @State private var edit = false

    private var student: Student? { repo.students.first { $0.id == studentID } }
    private var assigned: [ClassCourse] {
        repo.classes.filter { course in repo.enrollments.contains { $0.studentID == studentID && $0.classID == course.id && $0.endsOn == nil } }
    }

    var body: some View {
        Group {
            if let student {
                List {
                    Section {
                        VStack(spacing: 10) {
                            AvatarView(student: student, size: 88)
                            Text(student.fullName).font(.title2.bold())
                            Text(student.gradeLabel).foregroundStyle(AppTheme.muted)
                            if !student.active { Label("Inactive", systemImage: "archivebox.fill").foregroundStyle(.orange) }
                        }.frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    if !student.contact.isEmpty || !(student.emergencyContact ?? "").isEmpty {
                        Section("Contact") {
                            if !student.contact.isEmpty { LabeledContent("Student or parent", value: student.contact) }
                            if let emergency = student.emergencyContact, !emergency.isEmpty { LabeledContent("Emergency", value: emergency) }
                        }
                    }
                    Section("Assigned classes") {
                        if assigned.isEmpty { Text("No assigned classes.").foregroundStyle(AppTheme.muted) }
                        ForEach(assigned) { course in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(course.displayName)
                                Text(course.timeLabel).font(.caption).foregroundStyle(AppTheme.muted)
                            }
                        }
                    }
                    if !student.notes.isEmpty { Section("Notes") { Text(student.notes) } }
                }
            } else {
                ContentUnavailableView("Student unavailable", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .navigationTitle("Student profile").navigationBarTitleDisplayMode(.inline)
        .toolbar { if student != nil { Button("Edit Student") { edit = true } } }
        .sheet(isPresented: $edit) {
            if let student { NavigationStack { StudentEditorView(student: student) } }
        }
    }
}

struct StudentEditorView: View {
    @EnvironmentObject private var repo: LocalAttendanceRepository
    @Environment(\.dismiss) private var dismiss
    let original: Student
    @State private var first: String
    @State private var last: String
    @State private var grade: GradeOption?
    @State private var contact: String
    @State private var emergency: String
    @State private var notes: String
    @State private var active: Bool
    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var assigned: Set<UUID> = []
    @State private var baselineAssigned: Set<UUID> = []
    @State private var confirmDelete = false

    init(student: Student) {
        original = student
        _first = State(initialValue: student.firstName)
        _last = State(initialValue: student.lastName)
        _grade = State(initialValue: GradeOption(rawValue: student.grade))
        _contact = State(initialValue: student.contact)
        _emergency = State(initialValue: student.emergencyContact ?? "")
        _notes = State(initialValue: student.notes)
        _active = State(initialValue: student.active)
        _photoData = State(initialValue: student.photoData)
    }

    var body: some View {
        Form {
            Section("Profile photo") {
                HStack {
                    AvatarView(student: previewStudent, size: 62)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(photoData == nil ? "Choose photo" : "Change photo", systemImage: "photo")
                    }
                    if photoData != nil { Button("Remove", role: .destructive) { photoData = nil } }
                }
            }
            Section("Student") {
                TextField("First name", text: $first)
                TextField("Last name", text: $last)
                Picker("Grade", selection: $grade) {
                    Text("Select grade").tag(nil as GradeOption?)
                    ForEach(GradeOption.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }
                Toggle("Active student", isOn: $active)
            }
            Section("Contact") {
                TextField("Student or parent contact", text: $contact)
                TextField("Emergency contact", text: $emergency)
            }
            Section("Assigned classes") {
                if repo.classes.isEmpty { Text("No classes available.").foregroundStyle(AppTheme.muted) }
                ForEach(repo.classes) { course in
                    Toggle(isOn: assignmentBinding(course.id)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(course.displayName)
                            Text(course.timeLabel).font(.caption).foregroundStyle(AppTheme.muted)
                        }
                    }
                }
            }
            Section("Notes") { TextField("Notes", text: $notes, axis: .vertical) }
            Section { Button("Delete student", role: .destructive) { confirmDelete = true } }
            if let error = repo.lastError { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("Edit Student").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!valid || !changed) }
        }
        .onAppear {
            let ids = Set(repo.enrollments.filter { $0.studentID == original.id && $0.endsOn == nil }.map(\.classID))
            assigned = ids
            baselineAssigned = ids
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { if let data = try? await item.loadTransferable(type: Data.self) { photoData = data } }
        }
        .alert("Delete this student?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button(hasHistory ? "Archive" : "Delete", role: .destructive) {
                if repo.deleteOrArchiveStudent(id: original.id) { dismiss() }
            }
        } message: {
            Text(hasHistory ? "This student has attendance history and will be archived. Reports and historical attendance will remain intact." : "This permanently removes the student and current class assignments.")
        }
    }

    private var hasHistory: Bool {
        repo.attendance.contains { $0.studentID == original.id } || repo.makeupCredits.contains { $0.studentID == original.id }
    }
    private var previewStudent: Student {
        var value = original
        value.firstName = first; value.lastName = last; value.photoData = photoData
        return value
    }
    private var valid: Bool {
        !first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && grade != nil
    }
    private var changed: Bool {
        first != original.firstName || last != original.lastName || grade?.rawValue != original.grade || contact != original.contact || emergency != (original.emergencyContact ?? "") || notes != original.notes || active != original.active || photoData != original.photoData || assigned != baselineAssigned
    }
    private func assignmentBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { assigned.contains(id) }, set: { value in if value { assigned.insert(id) } else { assigned.remove(id) } })
    }
    private func save() {
        guard let grade else { return }
        var student = original
        student.firstName = first.trimmingCharacters(in: .whitespacesAndNewlines)
        student.lastName = last.trimmingCharacters(in: .whitespacesAndNewlines)
        student.grade = grade.rawValue
        student.contact = contact
        student.emergencyContact = emergency
        student.notes = notes
        student.isActive = active
        student.photoData = photoData
        guard repo.updateStudent(student) else { return }
        for course in repo.classes {
            repo.setEnrollment(studentID: student.id, classID: course.id, assigned: assigned.contains(course.id))
        }
        dismiss()
    }
}
