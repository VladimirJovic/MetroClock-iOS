import SwiftUI
import FirebaseFirestore

struct ClockView: View {
    @Environment(AuthService.self) var authService
    var workspaceService: WorkspaceService
    var taskService: TaskService

    @State private var clockService = ClockService()
    @State private var wifiService = WiFiService()
    @State private var showOvertimeSheet = false
    @State private var showTaskSheet = false
    @State private var showDayOffAlert = false
    @State private var dayOffAlertMessage = ""
    @State private var conflictingRequest: Request? = nil
    @State private var selectedTasks: Set<ExternalTask> = []
    @State private var overtimeNote = ""
    @State private var currentTime = Date()

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var user: MCUser? { authService.currentUser }
    var matchedOfficeByWiFi: MCOffice? {
        guard let ssid = wifiService.currentSSID, !ssid.isEmpty else { return nil }
        return workspaceService.offices.first { $0.ssid == ssid }
    }
    var matchedOfficeByGPS: MCOffice? { workspaceService.nearestOffice }
    var isLocationVerified: Bool { matchedOfficeByWiFi != nil || matchedOfficeByGPS != nil }

    var locationLabel: String {
        if let office = matchedOfficeByWiFi { return "\(office.name) — WiFi" }
        if let office = matchedOfficeByGPS  { return "\(office.name) — GPS" }
        return "Outside Office"
    }
    var workedToday: String {
        let total = clockService.calculateOfficeHoursToNow()
        guard total > 0 else { return "0h 0m" }
        let seconds = Int(total * 3600)
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }
    var plannedHoursToday: Double {
        guard let user = user else { return 0 }
        let dow = Calendar.current.component(.weekday, from: Date()) - 1
        return user.dailyHours?[String(dow)] ?? 0
    }

    // MARK: - Date string
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE — d MMMM yyyy"
        return formatter.string(from: currentTime).uppercased()
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            Color.mcBackground.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Header ──────────────────────────────────────────
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Good \(timeOfDay)")
                            .font(.system(size: 11, weight: .medium))
                            .tracking(3.5)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.mcTextSecondary)

                        Text(user?.firstName ?? "—")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.mcText)
                    }
                    Spacer()
                    StatusChip(isClockedIn: clockService.isClockedIn)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)

                Spacer()

                // ── Flip Clock ───────────────────────────────────────
                FlipClockView()

                Text(dateString)
                    .font(.system(size: 11, weight: .regular))
                    .tracking(3.0)
                    .foregroundStyle(Color.mcTextFaint)
                    .padding(.top, 20)

                // Worked today (only when clocked in)
                if clockService.isClockedIn {
                    Text(workedToday)
                        .font(.system(size: 13, weight: .medium))
                        .tracking(1.5)
                        .foregroundStyle(Color.mcTextTertiary)
                        .padding(.top, 8)
                }

                // Active tasks
                if clockService.isClockedIn && !selectedTasks.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(Array(selectedTasks)) { task in
                            Text("· \(task.displayName)")
                                .font(.system(size: 10, weight: .medium))
                                .tracking(1.0)
                                .textCase(.uppercase)
                                .foregroundStyle(Color.mcTextTertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 6)
                }

                Spacer()

                // ── Holographic Button ───────────────────────────────
                HolographicButton(
                    isClockedIn: clockService.isClockedIn,
                    isEnabled: isLocationVerified || clockService.isClockedIn,
                    isLoading: clockService.isLoading
                ) {
                    handleClockAction()
                }

                // Location / not-at-office message
                Group {
                    if !isLocationVerified && !clockService.isClockedIn {
                        Text("You must be at an office location to clock in")
                            .font(.system(size: 11, weight: .regular))
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.mcTextFaint)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    } else {
                        LocationIndicator(text: locationLabel)
                    }
                }
                .padding(.top, 18)

                Spacer(minLength: 16)
            }
        }
        .onAppear {
            wifiService.getCurrentSSID()
            if let user = user { clockService.fetchTodayEvents(userId: user.id) }
            taskService.refresh()
        }
        .onReceive(timer) { _ in currentTime = Date(); wifiService.getCurrentSSID() }
        .sheet(isPresented: $showTaskSheet) {
            TaskSelectionSheet(taskService: taskService, selectedTasks: $selectedTasks) { performClockIn() }
        }
        .sheet(isPresented: $showOvertimeSheet) {
            OvertimeNoteSheet(note: $overtimeNote) {
                performClockOut(note: overtimeNote)
                showOvertimeSheet = false; overtimeNote = ""
            } onCancel: {
                showOvertimeSheet = false; overtimeNote = ""
            }
        }
        .alert("Day Off / Sick Leave", isPresented: $showDayOffAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clock In Anyway") {
                if let req = conflictingRequest {
                    splitRequestExcludingToday(request: req) { proceedWithClockIn() }
                } else { proceedWithClockIn() }
            }
        } message: { Text(dayOffAlertMessage) }
        .alert("Error", isPresented: Binding(
            get: { clockService.errorMessage != nil },
            set: { if !$0 { clockService.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { clockService.errorMessage = nil }
        } message: {
            Text(clockService.errorMessage ?? "")
        }
    }

    // MARK: - Helpers
    private var timeOfDay: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "morning" }
        if h < 17 { return "afternoon" }
        return "evening"
    }

    // MARK: - Business Logic (unchanged)
    func handleClockAction() {
        guard let user = user else { return }
        if clockService.isClockedIn {
            clockService.checkOvertimeBeforeClockOut(userId: user.id, workspaceId: user.workspaceId, plannedHours: plannedHoursToday) { isOvertime in
                if isOvertime { showOvertimeSheet = true } else { performClockOut(note: nil) }
            }
        } else {
            checkDayOffConflict()
        }
    }

    func checkDayOffConflict() {
        guard let user = user else { return }
        let today = Calendar.current.startOfDay(for: Date())
        Firestore.firestore().collection("requests")
            .whereField("userId", isEqualTo: user.id)
            .whereField("status", isEqualTo: "approved")
            .getDocuments { snapshot, _ in
                let conflicts = snapshot?.documents.compactMap { doc -> Request? in
                    guard let req = parseRequest(doc: doc) else { return nil }
                    guard req.type == .dayOff || req.type == .sickLeave else { return nil }
                    return req.contains(date: today) ? req : nil
                } ?? []
                if let conflict = conflicts.first {
                    let label = conflict.type == .dayOff ? "Day Off" : "Sick Leave"
                    dayOffAlertMessage = "Today is marked as \(label). Clocking in will remove today from that request."
                    conflictingRequest = conflict
                    showDayOffAlert = true
                } else { proceedWithClockIn() }
            }
    }

    func proceedWithClockIn() {
        if taskService.isAvailable && !taskService.tasks.isEmpty { showTaskSheet = true }
        else { performClockIn() }
    }

    func splitRequestExcludingToday(request: Request, completion: @escaping () -> Void) {
        let db = Firestore.firestore()
        let today = Calendar.current.startOfDay(for: Date())
        let cal = Calendar.current
        let batch = db.batch()

        // Delete original atomically with the new segments
        batch.deleteDocument(db.collection("requests").document(request.id))

        let dayBefore = cal.date(byAdding: .day, value: -1, to: today)!
        let fromDay = cal.startOfDay(for: request.dateFrom)
        if fromDay < today {
            let ref = db.collection("requests").document()
            batch.setData(makeRequestData(original: request, dateFrom: request.dateFrom, dateTo: dayBefore), forDocument: ref)
        }

        let dayAfter = cal.date(byAdding: .day, value: 1, to: today)!
        let toDay = cal.startOfDay(for: request.dateTo)
        if toDay > today {
            let ref = db.collection("requests").document()
            batch.setData(makeRequestData(original: request, dateFrom: dayAfter, dateTo: request.dateTo), forDocument: ref)
        }

        batch.commit { _ in
            DispatchQueue.main.async { completion() }
        }
    }

    func makeRequestData(original: Request, dateFrom: Date, dateTo: Date) -> [String: Any] {
        var data: [String: Any] = [
            "userId": original.userId, "workspaceId": original.workspaceId,
            "managerId": original.managerId, "type": original.type.rawValue,
            "status": original.status.rawValue,
            "date": Timestamp(date: dateFrom), "dateFrom": Timestamp(date: dateFrom),
            "dateTo": Timestamp(date: dateTo), "createdAt": Timestamp(date: Date())
        ]
        if let note = original.employeeNote { data["employeeNote"] = note }
        if let note = original.managerNote { data["managerNote"] = note }
        return data
    }

    func performClockIn() {
        guard let user = user else { return }
        let locationId = matchedOfficeByWiFi?.id ?? matchedOfficeByGPS?.id ?? "unknown"
        let taskIds = selectedTasks.map { $0.id }
        clockService.clockIn(userId: user.id, workspaceId: user.workspaceId, locationId: locationId,
                             taskIds: taskIds.isEmpty ? nil : taskIds)
    }

    func performClockOut(note: String?) {
        guard let user = user else { return }
        let locationId = matchedOfficeByWiFi?.id ?? matchedOfficeByGPS?.id ?? "unknown"
        clockService.clockOut(userId: user.id, workspaceId: user.workspaceId, locationId: locationId,
                              overtimeNote: note, managerId: user.managerId, plannedHours: plannedHoursToday)
    }
}

// MARK: - TaskSelectionSheet
struct TaskSelectionSheet: View {
    var taskService: TaskService
    @Binding var selectedTasks: Set<ExternalTask>
    var onConfirm: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack { Color.mcBackground.ignoresSafeArea()
                Group {
                    if taskService.isLoading {
                        ProgressView().tint(Color.mcOrange).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if taskService.tasks.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle").font(.system(size: 48)).foregroundStyle(Color.mcTextTertiary)
                            Text("No tasks assigned").foregroundStyle(Color.mcTextSecondary)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            Section {
                                ForEach(taskService.tasks) { task in
                                    Button {
                                        if selectedTasks.contains(task) { selectedTasks.remove(task) }
                                        else { selectedTasks.insert(task) }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: selectedTasks.contains(task) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selectedTasks.contains(task) ? Color.mcOrange : Color.mcTextSecondary)
                                                .font(.system(size: 20))
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(task.displayName).font(.subheadline).fontWeight(.medium).foregroundStyle(Color.mcText).lineLimit(2)
                                                Text(task.status).font(.caption).foregroundStyle(Color.mcTextSecondary)
                                            }
                                            Spacer()
                                        }.padding(.vertical, 2)
                                    }.buttonStyle(.plain)
                                }
                            } header: { Text("Select tasks you're working on").foregroundStyle(Color.mcTextSecondary) }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("What are you working on?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") { dismiss(); onConfirm() }.foregroundStyle(Color.mcTextSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clock In") { dismiss(); onConfirm() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.mcOrange)
                        .disabled(taskService.isLoading)
                }
            }
        }.presentationDetents([.large])
    }
}

// MARK: - OvertimeNoteSheet
struct OvertimeNoteSheet: View {
    @Binding var note: String
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack { Color.mcBackground.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Text("You have worked more than your planned hours today. Please explain why.")
                        .font(.subheadline).foregroundStyle(Color.mcTextSecondary)
                    TextEditor(text: $note)
                        .frame(height: 120).padding(8)
                        .background(Color.mcSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.mcBorder, lineWidth: 1))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(Color.mcText)
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Overtime Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Submit") { onConfirm() }
                        .foregroundStyle(Color.mcOrange)
                        .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }.foregroundStyle(Color.mcTextSecondary)
                }
            }
        }.presentationDetents([.medium])
    }
}
