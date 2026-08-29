import SwiftUI

enum AppTheme {
    static let ink = Color(red: 0.10, green: 0.11, blue: 0.15)
    static let muted = Color(red: 0.42, green: 0.44, blue: 0.50)
    static let background = Color(red: 0.965, green: 0.958, blue: 0.94)
    static let card = Color.white
    static let accent = Color(red: 0.95, green: 0.39, blue: 0.30)
    static let deep = Color(red: 0.25, green: 0.20, blue: 0.54)
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppTheme.ink.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.28))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.75))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct AvatarView: View {
    let student: Student
    var size: CGFloat = 46
    var body: some View {
        Text(student.initials)
            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
            .frame(width: size, height: size)
            .background(AppTheme.deep.opacity(0.12))
            .foregroundStyle(AppTheme.deep)
            .clipShape(Circle())
    }
}

extension View {
    func cardStyle() -> some View {
        padding(18).background(AppTheme.card).clipShape(RoundedRectangle(cornerRadius: 24)).shadow(color: .black.opacity(0.045), radius: 14, y: 5)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(AppTheme.deep)
                .frame(width: 70, height: 70)
                .background(AppTheme.deep.opacity(0.1))
                .clipShape(Circle())
            Text(title).font(.title3.bold()).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.deep)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}
