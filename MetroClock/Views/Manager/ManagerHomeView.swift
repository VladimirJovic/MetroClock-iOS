import SwiftUI

struct ManagerHomeView: View {
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
    }
}
