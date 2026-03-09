import SwiftUI
import Combine

struct ClockView: View {
    @Environment(AuthService.self) var authService
    @State private var clockService = ClockService()
    @State private var wifiService = WiFiService()
    @State private var workspaceService = WorkspaceService()
    @State private var showOvertimeSheet = false
    @State private var overtimeNote = ""
    @State private var currentTime = Date()

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var user: MCUser? { authService.currentUser }

    var matchedOfficeByWiFi: MCOffice? {
        guard let ssid = wifiService.currentSSID, !ssid.isEmpty else { return nil }
        return workspaceService.offices.first { $0.ssid == ssid }
    }

    var matchedOfficeByGPS: MCOffice? {
        workspaceService.nearestOffice
    }

    var isLocationVerified: Bool {
        matchedOfficeByWiFi != nil || matchedOfficeByGPS != nil
    }

    var locationLabel: String {
        if let office = matchedOfficeByWiFi { return "\(office.name) (WiFi)" }
        if let office = matchedOfficeByGPS  { return "\(office.name) (GPS)" }
        return "Outside Office"
    }

    var locationIcon: String {
        if matchedOfficeByWiFi != nil { return "wifi" }
        if matchedOfficeByGPS  != nil { return "location.fill" }
        return "location.slash.fill"
    }

    var workedToday: String {
        guard let clockIn = clockService.lastClockIn else { return "0h 0m" }
        let seconds = Int(Date().timeIntervalSince(clockIn.timestamp))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    var plannedHoursToday: Double {
        guard let user = user else { return 8 }
        let dow = Calendar.current.component(.weekday, from: Date()) - 1
        return user.dailyHours?[String(dow)] ?? 8
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                VStack(spacing: 4) {
                    Text(currentTime, style: .time)
                        .font(.system(size: 56, weight: .thin, design: .monospaced))
                    Text(currentTime, style: .date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)
                .padding(.bottom, 32)

                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Status")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(clockService.isClockedIn ? "Clocked In" : "Clocked Out")
                                .font(.headline)
                                .foregroundStyle(clockService.isClockedIn ? .green : .red)
                        }
                        Spacer()
                        Circle()
                            .fill(clockService.isClockedIn ? Color.green : Color.red)
                            .frame(width: 12, height: 12)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Worked today")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(clockService.isClockedIn ? workedToday : "—")
                                .font(.headline)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Location")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Image(systemName: locationIcon)
                                    .foregroundStyle(isLocationVerified ? .green : .red)
                                Text(locationLabel)
                                    .font(.headline)
                            }
                        }
                    }
                }
                .padding(20)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .padding(.horizontal, 24)

                Spacer()

                Button {
                    handleClockAction()
                } label: {
                    Group {
                        if clockService.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: clockService.isClockedIn ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 32))
                                Text(clockService.isClockedIn ? "Clock Out" : "Clock In")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .frame(width: 160, height: 160)
                    .background(clockService.isClockedIn ? Color.red : Color.green)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
                    .shadow(color: clockService.isClockedIn ? .red.opacity(0.4) : .green.opacity(0.4), radius: 20)
                }
                .disabled((!isLocationVerified && !clockService.isClockedIn) || clockService.isLoading)
                .opacity((!isLocationVerified && !clockService.isClockedIn) ? 0.4 : 1.0)

                if !isLocationVerified && !clockService.isClockedIn {
                    Text("You must be at an office location to clock in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 12)
                }

                Spacer()
            }
            .navigationTitle("MetroClock")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                wifiService.getCurrentSSID()
                if let user = user {
                    clockService.fetchTodayEvents(userId: user.id)
                    workspaceService.fetchOffices(workspaceId: user.workspaceId)
                }
            }
            .onReceive(timer) { _ in
                currentTime = Date()
                wifiService.getCurrentSSID()
            }
            .sheet(isPresented: $showOvertimeSheet) {
                OvertimeNoteSheet(note: $overtimeNote) {
                    performClockOut(note: overtimeNote)
                    showOvertimeSheet = false
                    overtimeNote = ""
                }
            }
        }
    }

    func handleClockAction() {
        guard let user = user else { return }

        if clockService.isClockedIn {
            clockService.checkOvertimeBeforeClockOut(
                userId: user.id,
                workspaceId: user.workspaceId,
                plannedHours: plannedHoursToday
            ) { isOvertime in
                if isOvertime {
                    showOvertimeSheet = true
                } else {
                    performClockOut(note: nil)
                }
            }
        } else {
            let locationId: String
            if let office = matchedOfficeByWiFi      { locationId = office.id }
            else if let office = matchedOfficeByGPS  { locationId = office.id }
            else                                      { locationId = "unknown" }
            clockService.clockIn(
                userId: user.id,
                workspaceId: user.workspaceId,
                locationId: locationId
            )
        }
    }

    func performClockOut(note: String?) {
        guard let user = user else { return }
        let locationId: String
        if let office = matchedOfficeByWiFi      { locationId = office.id }
        else if let office = matchedOfficeByGPS  { locationId = office.id }
        else                                      { locationId = "unknown" }

        clockService.clockOut(
            userId: user.id,
            workspaceId: user.workspaceId,
            locationId: locationId,
            overtimeNote: note,
            managerId: user.managerId,
            plannedHours: plannedHoursToday
        )
    }
}

struct OvertimeNoteSheet: View {
    @Binding var note: String
    var onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("You have worked more than your planned hours today. Please explain why.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $note)
                    .frame(height: 120)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                Spacer()
            }
            .padding(24)
            .navigationTitle("Overtime Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Submit") { onConfirm() }
                        .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onConfirm() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
