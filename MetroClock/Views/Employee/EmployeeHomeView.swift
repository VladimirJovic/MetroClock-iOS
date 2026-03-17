import SwiftUI

struct EmployeeHomeView: View {
    @Environment(AuthService.self) var authService
    @State private var workspaceService = WorkspaceService()
    @State private var taskService = TaskService()

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

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
        }
        .onAppear {
            if let user = authService.currentUser {
                workspaceService.fetchOffices(workspaceId: user.workspaceId)
                workspaceService.fetchWorkspaceConfig(workspaceId: user.workspaceId)
            }
        }
        .onChange(of: workspaceService.config.clickupApiToken) { _, _ in
            // When config loads, fetch tasks if available
            if let user = authService.currentUser {
                taskService.fetchTasks(config: workspaceService.config, metroUserId: user.id)
            }
        }
    }
}
