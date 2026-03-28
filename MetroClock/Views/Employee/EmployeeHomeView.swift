import SwiftUI

struct EmployeeHomeView: View {
    @Environment(AuthService.self) var authService
    @State private var workspaceService = WorkspaceService()
    @State private var taskService = TaskService()
    @State private var badgeService = BadgeService()

    var body: some View {
        TabView {
            ClockView(workspaceService: workspaceService, taskService: taskService)
                .tabItem {
                    Label("Clock", systemImage: "clock.fill")
                }

            MyHoursView()
                .tabItem {
                    Label("My Hours", systemImage: "calendar")
                }

            RequestsView(workspaceService: workspaceService, taskService: taskService)
                .tabItem {
                    Label("Requests", systemImage: "paperplane.fill")
                }
                .badge(badgeService.employeeBadgeCount)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
        }
        .environment(badgeService)
        .onAppear {
            if let user = authService.currentUser {
                workspaceService.fetchOffices(workspaceId: user.workspaceId)
                workspaceService.fetchWorkspaceConfig(workspaceId: user.workspaceId)
                badgeService.startListening(for: user)
            }
        }
        .onChange(of: workspaceService.config.clickupApiToken) { _, _ in
            if let user = authService.currentUser {
                taskService.fetchTasks(config: workspaceService.config, metroUserId: user.id)
            }
        }
        .tint(Color.mcOrange)
        .toolbarBackground(Color.mcBackground, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
