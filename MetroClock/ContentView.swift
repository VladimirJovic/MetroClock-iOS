import SwiftUI

struct ContentView: View {
    @Environment(AuthService.self) var authService
    
    var body: some View {
        if authService.isAuthenticated {
            switch authService.currentUser?.role {
            case .admin:
                VStack {
                    Text("Admin panel - coming soon")
                    Button("Logout") { authService.logout() }
                }
            case .manager:
                ManagerHomeView()
            case .employee:
                EmployeeHomeView()
            case .none:
                LoginView()
            }
        } else {
            LoginView()
        }
    }
}
