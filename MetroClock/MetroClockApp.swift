import SwiftUI
import FirebaseCore

@main
struct MetroClockApp: App {
    @State private var authService: AuthService
    
    init() {
        FirebaseApp.configure()
        _authService = State(initialValue: AuthService())
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
        }
    }
}
