import SwiftUI
import FirebaseFirestore

struct RequestsView: View {
    @Environment(AuthService.self) var authService
    @Environment(BadgeService.self) var badgeService
    var workspaceService: WorkspaceService
    var taskService: TaskService

    @State private var requests: [Request] = []
    @State private var isLoading = true
    @State private var showNewRequest = false

    var body: some View {
        NavigationStack {
            ZStack { Color.mcBackground.ignoresSafeArea()
                Group {
                    if isLoading {
                        ProgressView().tint(Color.mcOrange)
                    } else if requests.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "paperplane")
                                .font(.system(size: 48))
                                .foregroundStyle(Color.mcTextTertiary)
                            Text("No requests yet")
                                .foregroundStyle(Color.mcTextSecondary)
                        }
                    } else {
                        List {
                            ForEach(requests) { request in
                                RequestRowView(request: request)
                                    .listRowBackground(Color.mcSurface)
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Requests")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewRequest = true } label: { Image(systemName: "plus") }
                        .foregroundStyle(Color.mcOrange)
                }
            }
            .onAppear {
                if let userId = authService.currentUser?.id {
                    fetchRequests(userId: userId)
                }
                taskService.refresh()
            }
            .onChange(of: requests.map(\.id)) { _, _ in
                // Mark all resolved requests as seen when the tab is open
                let resolvedIds = requests
                    .filter { $0.status != .pending }
                    .map { $0.id }
                if !resolvedIds.isEmpty {
                    badgeService.markAllResolvedAsSeen(ids: resolvedIds)
                }
            }
            .sheet(isPresented: $showNewRequest) {
                NewRequestSheet(
                    taskService: taskService,
                    existingRequests: requests,
                    onSubmit: { type, dateFrom, dateTo, note, hours, taskIds in
                        submitRequest(type: type, dateFrom: dateFrom, dateTo: dateTo, note: note, hours: hours, taskIds: taskIds)
                    }
                )
            }
        }
    }

    func fetchRequests(userId: String) {
        let db = Firestore.firestore()
        db.collection("requests")
            .whereField("userId", isEqualTo: userId)
            .getDocuments { snapshot, error in
                isLoading = false
                guard let docs = snapshot?.documents else { return }
                requests = docs.compactMap { parseRequest(doc: $0) }
                    .sorted { $0.createdAt > $1.createdAt }
            }
    }

    func submitRequest(type: RequestType, dateFrom: Date, dateTo: Date, note: String, hours: Double?, taskIds: [String]) {
        guard let user = authService.currentUser else { return }
        let db = Firestore.firestore()

        // Find overlapping requests of same type to delete
        let overlapping = requests.filter { req in
            guard req.type == type else { return false }
            return req.allDates.contains { reqDate in
                let d = Calendar.current.startOfDay(for: reqDate)
                let from = Calendar.current.startOfDay(for: dateFrom)
                let to = Calendar.current.startOfDay(for: dateTo)
                return d >= from && d <= to
            }
        }

        let group = DispatchGroup()
        for req in overlapping {
            group.enter()
            db.collection("requests").document(req.id).delete { _ in group.leave() }
        }

        group.notify(queue: .main) {
            var data: [String: Any] = [
                "userId": user.id,
                "workspaceId": user.workspaceId,
                "managerId": user.managerId ?? "",
                "type": type.rawValue,
                "status": "pending",
                "date": Timestamp(date: dateFrom),
                "dateFrom": Timestamp(date: dateFrom),
                "dateTo": Timestamp(date: dateTo),
                "employeeNote": note,
                "createdAt": Timestamp(date: Date())
            ]
            if type == .remoteWork, let h = hours { data["remoteHours"] = h }
            if !taskIds.isEmpty { data["taskIds"] = taskIds }

            db.collection("requests").addDocument(data: data) { error in
                if error == nil {
                    showNewRequest = false
                    fetchRequests(userId: user.id)
                    if let managerId = user.managerId, !managerId.isEmpty {
                        // Notification sent automatically by Cloud Function (onRequestCreated)
                    }
                }
            }
        }
    }
}

// MARK: - Parse helper

func parseRequest(doc: QueryDocumentSnapshot) -> Request? {
    let data = doc.data()
    guard let typeStr = data["type"] as? String,
          let type = RequestType(rawValue: typeStr),
          let statusStr = data["status"] as? String,
          let status = RequestStatus(rawValue: statusStr) else { return nil }

    let dateFrom = (data["dateFrom"] as? Timestamp)?.dateValue()
        ?? (data["date"] as? Timestamp)?.dateValue()
        ?? Date()
    let dateTo = (data["dateTo"] as? Timestamp)?.dateValue() ?? dateFrom

    return Request(
        id: doc.documentID,
        userId: data["userId"] as? String ?? "",
        workspaceId: data["workspaceId"] as? String ?? "",
        managerId: data["managerId"] as? String ?? "",
        type: type, status: status,
        date: dateFrom, dateFrom: dateFrom, dateTo: dateTo,
        employeeNote: data["employeeNote"] as? String,
        managerNote: data["managerNote"] as? String,
        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
        remoteHours: (data["remoteHours"] as? Double) ?? (data["remoteHours"] as? Int).map { Double($0) }
    )
}

// MARK: - RequestRowView

struct RequestRowView: View {
    var request: Request

    var typeLabel: String {
        switch request.type {
        case .remoteWork:
            if let h = request.remoteHours {
                let display = h.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(h))h" : String(format: "%.1fh", h)
                return "Remote Work · \(display)"
            }
            return "Remote Work"
        case .sickLeave: return "Sick Leave"
        case .dayOff:    return "Day Off"
        case .overtime:  return "Overtime"
        }
    }

    var typeIcon: String {
        switch request.type {
        case .remoteWork: return "house.fill"
        case .sickLeave:  return "cross.fill"
        case .dayOff:     return "sun.max.fill"
        case .overtime:   return "clock.badge.exclamationmark.fill"
        }
    }

    var statusColor: Color {
        switch request.status {
        case .pending:  return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(statusColor.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: typeIcon).foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(typeLabel).font(.subheadline).fontWeight(.medium)
                Text(request.dateRangeLabel).font(.caption).foregroundStyle(.secondary)
                if let note = request.managerNote, !note.isEmpty {
                    Text("Manager: \(note)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(request.status.rawValue.capitalized)
                .font(.caption).fontWeight(.semibold).foregroundStyle(statusColor)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(statusColor.opacity(0.12)).cornerRadius(8)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - NewRequestSheet

struct NewRequestSheet: View {
    var taskService: TaskService
    var existingRequests: [Request]
    var onSubmit: (RequestType, Date, Date, String, Double?, [String]) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var selectedType: RequestType = .remoteWork
    @State private var dateFrom = Date()
    @State private var dateTo = Date()
    @State private var note = ""
    @State private var remoteHours: Double = 8
    @State private var selectedTasks: Set<ExternalTask> = []
    @State private var showOverlapAlert = false
    @State private var overlapMessage = ""

    var overlappingRequests: [Request] {
        guard selectedType != .remoteWork else { return [] }
        return existingRequests.filter { req in
            req.type == selectedType && req.allDates.contains { reqDate in
                let d = Calendar.current.startOfDay(for: reqDate)
                let from = Calendar.current.startOfDay(for: dateFrom)
                let to = Calendar.current.startOfDay(for: dateTo)
                return d >= from && d <= to
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Request Type") {
                    Picker("Type", selection: $selectedType) {
                        Text("Remote Work").tag(RequestType.remoteWork)
                        Text("Sick Leave").tag(RequestType.sickLeave)
                        Text("Day Off").tag(RequestType.dayOff)
                    }
                    .pickerStyle(.segmented)
                }

                if selectedType == .remoteWork {
                    Section("From") {
                        DatePicker("Start date", selection: $dateFrom, displayedComponents: .date)
                            .onChange(of: dateFrom) { _, new in if dateTo < new { dateTo = new } }
                    }
                    Section("To") {
                        DatePicker("End date", selection: $dateTo, in: dateFrom..., displayedComponents: .date)
                    }
                    Section("Hours per day working remote") {
                        Stepper(value: $remoteHours, in: 0.5...24, step: 0.5) {
                            HStack {
                                Text("Hours per day")
                                Spacer()
                                Text(remoteHours.truncatingRemainder(dividingBy: 1) == 0
                                     ? "\(Int(remoteHours))h"
                                     : String(format: "%.1fh", remoteHours))
                                    .fontWeight(.semibold).foregroundStyle(Color.mcOrange)
                            }
                        }
                    }
                    if taskService.isAvailable && !taskService.tasks.isEmpty {
                        Section("Tasks (optional)") {
                            ForEach(taskService.tasks) { task in
                                Button {
                                    if selectedTasks.contains(task) { selectedTasks.remove(task) }
                                    else { selectedTasks.insert(task) }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedTasks.contains(task) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedTasks.contains(task) ? Color.mcOrange : Color.mcTextSecondary)
                                        Text(task.displayName).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    Section("From") {
                        DatePicker("Start date", selection: $dateFrom, displayedComponents: .date)
                            .onChange(of: dateFrom) { _, new in if dateTo < new { dateTo = new } }
                    }
                    Section("To") {
                        DatePicker("End date", selection: $dateTo, in: dateFrom..., displayedComponents: .date)
                    }
                    if !overlappingRequests.isEmpty {
                        Section {
                            Label {
                                Text("You already have a \(selectedType == .sickLeave ? "Sick Leave" : "Day Off") request for some of these days. Submitting will replace it.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                Section("Note") {
                    TextEditor(text: $note).frame(height: 80)
                }
            }
            .navigationTitle("New Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Submit") { handleSubmit() }.fontWeight(.semibold)
                }
            }
            .alert("Replace Existing Request?", isPresented: $showOverlapAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Replace", role: .destructive) { doSubmit() }
            } message: {
                Text(overlapMessage)
            }
        }
    }

    func handleSubmit() {
        if !overlappingRequests.isEmpty {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .none
            let days = overlappingRequests.flatMap { $0.allDates }
                .filter {
                    let d = Calendar.current.startOfDay(for: $0)
                    let from = Calendar.current.startOfDay(for: dateFrom)
                    let to = Calendar.current.startOfDay(for: dateTo)
                    return d >= from && d <= to
                }
                .map { fmt.string(from: $0) }
                .joined(separator: ", ")
            overlapMessage = "Existing request covers: \(days). Submitting will delete it and replace with the new one."
            showOverlapAlert = true
        } else {
            doSubmit()
        }
    }

    func doSubmit() {
        let hours: Double? = selectedType == .remoteWork ? remoteHours : nil
        let taskIds = selectedTasks.map { $0.id }
        onSubmit(selectedType, dateFrom, dateTo, note, hours, taskIds)
    }
}
