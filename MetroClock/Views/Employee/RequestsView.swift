import SwiftUI
import FirebaseFirestore

struct RequestsView: View {
    @Environment(AuthService.self) var authService
    var workspaceService: WorkspaceService
    var taskService: TaskService

    @State private var requests: [Request] = []
    @State private var isLoading = true
    @State private var showNewRequest = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if requests.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "paperplane")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No requests yet")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        ForEach(requests) { request in
                            RequestRowView(request: request)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Requests")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewRequest = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                if let userId = authService.currentUser?.id {
                    fetchRequests(userId: userId)
                }
            }
            .sheet(isPresented: $showNewRequest) {
                NewRequestSheet(
                    taskService: taskService,
                    onSubmit: { type, date, note, hours, taskIds in
                        submitRequest(type: type, date: date, note: note, hours: hours, taskIds: taskIds)
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
                requests = docs.compactMap { doc in
                    let data = doc.data()
                    return Request(
                        id: doc.documentID,
                        userId: data["userId"] as? String ?? "",
                        workspaceId: data["workspaceId"] as? String ?? "",
                        managerId: data["managerId"] as? String ?? "",
                        type: RequestType(rawValue: data["type"] as? String ?? "remoteWork") ?? .remoteWork,
                        status: RequestStatus(rawValue: data["status"] as? String ?? "pending") ?? .pending,
                        date: (data["date"] as? Timestamp)?.dateValue() ?? Date(),
                        employeeNote: data["employeeNote"] as? String,
                        managerNote: data["managerNote"] as? String,
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                        remoteHours: data["remoteHours"] as? Double
                    )
                }.sorted { $0.createdAt > $1.createdAt }
            }
    }

    func submitRequest(type: RequestType, date: Date, note: String, hours: Double?, taskIds: [String]) {
        guard let user = authService.currentUser else { return }
        let db = Firestore.firestore()

        if type != .remoteWork {
            let calendar = Calendar.current
            let duplicate = requests.first { req in
                req.type == type && calendar.isDate(req.date, inSameDayAs: date)
            }
            if duplicate != nil { return }
        }

        var data: [String: Any] = [
            "userId": user.id,
            "workspaceId": user.workspaceId,
            "managerId": user.managerId ?? "",
            "type": type.rawValue,
            "status": "pending",
            "date": Timestamp(date: date),
            "employeeNote": note,
            "createdAt": Timestamp(date: Date())
        ]

        if type == .remoteWork, let h = hours {
            data["remoteHours"] = h
        }
        if !taskIds.isEmpty {
            data["taskIds"] = taskIds
        }

        db.collection("requests").addDocument(data: data) { error in
            if error == nil {
                showNewRequest = false
                fetchRequests(userId: user.id)
            }
        }
    }
}

// MARK: - RequestRowView

struct RequestRowView: View {
    var request: Request

    var typeLabel: String {
        switch request.type {
        case .remoteWork: return "Remote Work"
        case .sickLeave:  return "Sick Leave"
        case .dayOff:     return "Day Off"
        case .overtime:   return "Overtime"
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

    var statusLabel: String {
        switch request.status {
        case .pending:  return "Pending"
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: typeIcon)
                    .foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(typeLabel)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(request.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = request.managerNote, !note.isEmpty {
                    Text("Manager: \(note)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(statusLabel)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.12))
                .cornerRadius(8)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - NewRequestSheet

struct NewRequestSheet: View {
    var taskService: TaskService
    var onSubmit: (RequestType, Date, String, Double?, [String]) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var selectedType: RequestType = .remoteWork
    @State private var selectedDate = Date()
    @State private var note = ""
    @State private var remoteHours: Double = 8
    @State private var selectedTasks: Set<ExternalTask> = []

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

                Section("Date") {
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }

                if selectedType == .remoteWork {
                    Section("Hours working remote") {
                        Stepper(value: $remoteHours, in: 1...24, step: 0.5) {
                            HStack {
                                Text("Hours")
                                Spacer()
                                Text(remoteHours.truncatingRemainder(dividingBy: 1) == 0
                                     ? "\(Int(remoteHours))h"
                                     : String(format: "%.1fh", remoteHours))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    // Task selection — only for remote work and if tasks are available
                    if taskService.isAvailable && !taskService.tasks.isEmpty {
                        Section("Tasks (optional)") {
                            ForEach(taskService.tasks) { task in
                                Button {
                                    if selectedTasks.contains(task) {
                                        selectedTasks.remove(task)
                                    } else {
                                        selectedTasks.insert(task)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedTasks.contains(task) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedTasks.contains(task) ? .blue : .secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(task.name)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                                .lineLimit(2)
                                            if let list = task.listName {
                                                Text(list)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("Note") {
                    TextEditor(text: $note)
                        .frame(height: 80)
                }
            }
            .navigationTitle("New Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Submit") {
                        let hours: Double? = selectedType == .remoteWork ? remoteHours : nil
                        let taskIds = selectedTasks.map { $0.id }
                        onSubmit(selectedType, selectedDate, note, hours, taskIds)
                    }
                }
            }
        }
    }
}
