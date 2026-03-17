import SwiftUI

struct ManagerHomeView: View {
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

            TeamHoursView()
                .tabItem {
                    Label("Team", systemImage: "person.3.fill")
                }

            InboxView()
                .tabItem {
                    Label("Inbox", systemImage: "tray.fill")
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
            if let user = authService.currentUser {
                taskService.fetchTasks(config: workspaceService.config, metroUserId: user.id)
            }
        }
    }
}
