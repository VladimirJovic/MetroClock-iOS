import SwiftUI
import FirebaseFirestore

struct InboxView: View {
    @Environment(AuthService.self) var authService
    @State private var requests: [Request] = []
    @State private var isLoading = true
    
    var pendingRequests: [Request] { requests.filter { $0.status == .pending } }
    var resolvedRequests: [Request] { requests.filter { $0.status != .pending } }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if requests.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No requests")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        if !pendingRequests.isEmpty {
                            Section("Pending (\(pendingRequests.count))") {
                                ForEach(pendingRequests) { request in
                                    InboxRequestRow(request: request) { status, note in
                                        resolveRequest(request: request, status: status, note: note)
                                    }
                                }
                            }
                        }
                        if !resolvedRequests.isEmpty {
                            Section("Resolved") {
                                ForEach(resolvedRequests) { request in
                                    InboxRequestRow(request: request, onResolve: nil)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Inbox")
            .onAppear {
                if let managerId = authService.currentUser?.id {
                    fetchRequests(managerId: managerId)
                }
            }
        }
    }
    
    func fetchRequests(managerId: String) {
        let db = Firestore.firestore()
        db.collection("requests")
            .whereField("managerId", isEqualTo: managerId)
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
    
    func resolveRequest(request: Request, status: RequestStatus, note: String) {
        let db = Firestore.firestore()
        
        db.collection("requests").document(request.id).updateData([
            "status": status.rawValue,
            "managerNote": note
        ]) { error in
            guard error == nil else { return }
            
            // Ako je overtime request, azuriraj clockEvent
            if request.type == .overtime {
                let approved = status == .approved
                db.collection("clockEvents")
                    .whereField("userId", isEqualTo: request.userId)
                    .whereField("type", isEqualTo: "clockOut")
                    .getDocuments { snapshot, _ in
                        guard let docs = snapshot?.documents else { return }
                        // Nadji clockOut koji je najblizi datumu requesta
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
        }
    }
}

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
                    ? "\(Int(h))h"
                    : String(format: "%.1fh", h)
                return "Remote Work · \(display)"
            }
            return "Remote Work · Full Day"
        case .sickLeave: return "Sick Leave"
        case .dayOff: return "Day Off"
        case .overtime: return "Overtime"
        }
    }
    
    var typeIcon: String {
        switch request.type {
        case .remoteWork: return "house.fill"
        case .sickLeave: return "cross.fill"
        case .dayOff: return "sun.max.fill"
        case .overtime: return "clock.badge.exclamationmark.fill"
        }
    }
    
    var statusColor: Color {
        switch request.status {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: typeIcon)
                        .foregroundStyle(statusColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(typeLabel)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if !employeeName.isEmpty {
                            Text("· \(employeeName)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(request.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(request.status.rawValue.capitalized)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12))
                    .cornerRadius(8)
            }
            
            if let note = request.employeeNote, !note.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 52)
            }
            
            if let note = request.managerNote, !note.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 52)
            }
            
            if request.status == .pending, let onResolve = onResolve {
                Button {
                    showResolveSheet = true
                } label: {
                    Text("Respond")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.leading, 52)
                .sheet(isPresented: $showResolveSheet) {
                    ResolveRequestSheet { status, note in
                        onResolve(status, note)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            fetchEmployeeName()
        }
    }
    
    func fetchEmployeeName() {
        let db = Firestore.firestore()
        db.collection("users").document(request.userId).getDocument { snapshot, _ in
            if let data = snapshot?.data() {
                let first = data["firstName"] as? String ?? ""
                let last = data["lastName"] as? String ?? ""
                employeeName = "\(first) \(last)"
            }
        }
    }
}

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
                    TextEditor(text: $note)
                        .frame(height: 80)
                }
            }
            .navigationTitle("Respond to Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send") {
                        onResolve(selectedStatus, note)
                        dismiss()
                    }
                    .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
