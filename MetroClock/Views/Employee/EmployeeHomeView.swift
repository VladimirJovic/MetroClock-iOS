import SwiftUI

struct EmployeeHomeView: View {
    var body: some View {
        TabView {
            ClockView()
                .tabItem {
                    Label("Clock", systemImage: "clock.fill")
                }
            
            MyHoursView()
                .tabItem {
                    Label("My Hours", systemImage: "calendar")
                }
            
            RequestsView()
                .tabItem {
                    Label("Requests", systemImage: "paperplane.fill")
                }
            
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
        }
    }
}
