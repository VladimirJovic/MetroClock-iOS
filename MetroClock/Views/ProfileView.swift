import SwiftUI

struct ProfileView: View {
    @Environment(AuthService.self) var authService

    var user: MCUser? { authService.currentUser }

    var roleLabel: String {
        switch user?.role {
        case .admin: return "Admin"
        case .manager: return "Manager"
        case .employee: return "Employee"
        case .none: return ""
        }
    }

    var roleColor: Color {
        switch user?.role {
        case .admin: return .purple
        case .manager: return .mcOrange
        case .employee: return Color(red: 0.18, green: 0.83, blue: 0.49)
        case .none: return .gray
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(roleColor.opacity(0.15))
                                .frame(width: 64, height: 64)
                            Text((user?.firstName.prefix(1) ?? "") + (user?.lastName.prefix(1) ?? ""))
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(roleColor)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(user?.fullName ?? "")
                                .font(.headline)
                            Text(user?.email ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(roleLabel)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(roleColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(roleColor.opacity(0.12))
                                .cornerRadius(6)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Account") {
                    LabeledContent("First Name", value: user?.firstName ?? "")
                    LabeledContent("Last Name", value: user?.lastName ?? "")
                    LabeledContent("Email", value: user?.email ?? "")
                    LabeledContent("Role", value: roleLabel)
                }
                
                Section {
                    Button(role: .destructive) {
                        authService.logout()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.mcBackground.ignoresSafeArea())
            .navigationTitle("Profile")
        }
    }
}
