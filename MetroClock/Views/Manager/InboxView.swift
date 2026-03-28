import SwiftUI
import FirebaseFirestore

struct InboxView: View {
    @Environment(AuthService.self) var authService
    @State private var requests: [Request] = []
    @State private var isLoading = true
    @State private var showNewRequest = false

    var pendingRequests: [Request] { requests.filter { $0.status == .pending } }
    var resolvedRequests: [Request] { requests.filter { $0.status != .pending } }
    var hasManager: Bool { authService.currentUser?.managerId != nil }

    var body: some View {
        NavigationStack {
            ZStack { Color.mcBackground.ignoresSafeArea()
                Group {
                    if isLoading {
                        ProgressView().tint(Color.mcOrange)
                    } else if requests.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 48))
                                .foregroundStyle(Color.mcTextTertiary)
                            Text("No requests")
                                .foregroundStyle(Color.mcTextSecondary)
                        }
                    } else {
                        List {
                            if !pendingRequests.isEmpty {
                                Section("Pending (\(pendingRequests.count))") {
                                    ForEach(pendingRequests) { request in
                                        InboxRequestRow(request: request) { status, note in
                                            resolveRequest(request: request, status: status, note: note)
                                        }
                                        .listRowBackground(Color.mcSurface)
                                    }
                                }
                            }
                            if !resolvedRequests.isEmpty {
                                Section("Resolved") {
                                    ForEach(resolvedRequests) { request in
                                        InboxRequestRow(request: request, onResolve: nil)
                                            .listRowBackground(Color.mcSurface)
                                    }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                if hasManager {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showNewRequest = true } label: { Image(systemName: "plus") }
                    }
                }
            }
            .onAppear {
                if let managerId = authService.currentUser?.id {
                    fetchRequests(managerId: managerId)
                }
            }
            .sheet(isPresented: $showNewRequest) {
                ManagerNewRequestSheet { type, dateFrom, dateTo, note, hours in
                    submitRequest(type: type, dateFrom: dateFrom, dateTo: dateTo, note: note, hours: hours)
                }
            }
        }
    }

    func fetchRequests(managerId: String) {
        Firestore.firestore().collection("requests")
            .whereField("managerId", isEqualTo: managerId)
            .getDocuments { snapshot, error in
                isLoading = false
                guard let docs = snapshot?.documents else { return }
                requests = docs.compactMap { parseRequest(doc: $0) }
                    .sorted { $0.createdAt > $1.createdAt }
            }
    }

    func submitRequest(type: RequestType, dateFrom: Date, dateTo: Date, note: String, hours: Double?) {
        guard let user = authService.currentUser,
              let managerOfManager = user.managerId else { return }
        let db = Firestore.firestore()
        var data: [String: Any] = [
            "userId": user.id,
            "workspaceId": user.workspaceId,
            "managerId": managerOfManager,
            "type": type.rawValue,
            "status": "pending",
            "date": Timestamp(date: dateFrom),
            "dateFrom": Timestamp(date: dateFrom),
            "dateTo": Timestamp(date: dateTo),
            "employeeNote": note,
            "createdAt": Timestamp(date: Date())
        ]
        if type == .remoteWork, let h = hours { data["remoteHours"] = h }
        db.collection("requests").addDocument(data: data) { error in
            if error == nil { showNewRequest = false }
        }
    }

    func resolveRequest(request: Request, status: RequestStatus, note: String) {
        let db = Firestore.firestore()
        var updateData: [String: Any] = [
            "status": status.rawValue,
            "managerNote": note
        ]
        if status == .approved {
            updateData["approvedAt"] = Timestamp(date: Date())
        }
        db.collection("requests").document(request.id).updateData(updateData) { error in
            guard error == nil else { return }
            if request.type == .overtime {
                let approved = status == .approved
                db.collection("clockEvents")
                    .whereField("userId", isEqualTo: request.userId)
                    .whereField("type", isEqualTo: "clockOut")
                    .getDocuments { snapshot, _ in
                        guard let docs = snapshot?.documents else { return }
                        let requestDate = Calendar.current.startOfDay(for: request.date)
                        let matchingDoc = docs.first { doc in
                            let ts = (doc.data()["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                            return Calendar.current.startOfDay(for: ts) == requestDate
                        }
                        if let docId = matchingDoc?.documentID {
                            db.collection("clockEvents").document(docId).updateData([
                                "isOvertimeApproved": approved,
                                "managerNote": note
                            ])
                        }
                    }
            }
            if let managerId = authService.currentUser?.id {
                fetchRequests(managerId: managerId)
            }
            // Notification sent automatically by Cloud Function (onRequestUpdated)
        }
    }
}

// MARK: - ManagerNewRequestSheet

struct ManagerNewRequestSheet: View {
    var onSubmit: (RequestType, Date, Date, String, Double?) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var selectedType: RequestType = .remoteWork
    @State private var dateFrom = Date()
    @State private var dateTo = Date()
    @State private var note = ""
    @State private var remoteHours: Double = 8

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
                    Section("Date") {
                        DatePicker("Date", selection: $dateFrom, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .onChange(of: dateFrom) { _, new in dateTo = new }
                    }
                    Section("Hours working remote") {
                        Stepper(value: $remoteHours, in: 0.5...24, step: 0.5) {
                            HStack {
                                Text("Hours")
                                Spacer()
                                Text(remoteHours.truncatingRemainder(dividingBy: 1) == 0
                                     ? "\(Int(remoteHours))h"
                                     : String(format: "%.1fh", remoteHours))
                                    .fontWeight(.semibold).foregroundStyle(.blue)
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
                    Button("Submit") {
                        let hours: Double? = selectedType == .remoteWork ? remoteHours : nil
                        onSubmit(selectedType, dateFrom, dateTo, note, hours)
                    }
                }
            }
        }
    }
}

// MARK: - InboxRequestRow

struct InboxRequestRow: View {
    var request: Request
    var onResolve: ((RequestStatus, String) -> Void)?
    @State private var showResolveSheet = false
    @State private var employeeName = ""

    var typeLabel: String {
        switch request.type {
        case .remoteWork:
            if let h = request.remoteHours {
                let display = h.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(h))h" : String(format: "%.1fh", h)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(statusColor.opacity(0.15)).frame(width: 40, height: 40)
                    Image(systemName: typeIcon).foregroundStyle(statusColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(typeLabel).font(.subheadline).fontWeight(.medium)
                        if !employeeName.isEmpty {
                            Text("· \(employeeName)").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Text(request.dateRangeLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(request.status.rawValue.capitalized)
                    .font(.caption).fontWeight(.semibold).foregroundStyle(statusColor)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(statusColor.opacity(0.12)).cornerRadius(8)
            }

            if let note = request.employeeNote, !note.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble").font(.caption).foregroundStyle(.secondary)
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.leading, 52)
            }

            if let note = request.managerNote, !note.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left").font(.caption).foregroundStyle(.secondary)
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.leading, 52)
            }

            if request.status == .pending, let onResolve = onResolve {
                Button {
                    showResolveSheet = true
                } label: {
                    Text("Respond")
                        .font(.caption).fontWeight(.semibold)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Color.mcOrange.opacity(0.12)).foregroundStyle(Color.mcOrange).cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.leading, 52)
                .sheet(isPresented: $showResolveSheet) {
                    ResolveRequestSheet { status, note in onResolve(status, note) }
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear { fetchEmployeeName() }
    }

    func fetchEmployeeName() {
        Firestore.firestore().collection("users").document(request.userId).getDocument { snapshot, _ in
            if let data = snapshot?.data() {
                let first = data["firstName"] as? String ?? ""
                let last = data["lastName"] as? String ?? ""
                employeeName = "\(first) \(last)"
            }
        }
    }
}

// MARK: - ResolveRequestSheet

struct ResolveRequestSheet: View {
    var onResolve: (RequestStatus, String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var note = ""
    @State private var selectedStatus: RequestStatus = .approved

    var body: some View {
        NavigationStack {
            Form {
                Section("Decision") {
                    Picker("Status", selection: $selectedStatus) {
                        Text("Approve").tag(RequestStatus.approved)
                        Text("Reject").tag(RequestStatus.rejected)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Note (required)") {
                    TextEditor(text: $note).frame(height: 80)
                }
            }
            .navigationTitle("Respond to Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send") { onResolve(selectedStatus, note); dismiss() }
                        .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
