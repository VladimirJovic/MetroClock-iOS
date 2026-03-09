import SwiftUI
import FirebaseFirestore
import Kingfisher

struct TeamHoursView: View {
    @Environment(AuthService.self) var authService
    @State private var teamMembers: [MCUser] = []
    @State private var selectedUser: MCUser?
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if teamMembers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.3")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No team members")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List(teamMembers) { member in
                        Button {
                            selectedUser = member
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    if let urlString = member.profileImageURL,
                                       let url = URL(string: urlString) {
                                        KFImage(url)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 40, height: 40)
                                            .clipShape(Circle())
                                    } else {
                                        Circle()
                                            .fill(Color.blue.opacity(0.15))
                                            .frame(width: 40, height: 40)
                                        Text(member.firstName.prefix(1) + member.lastName.prefix(1))
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.blue)
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.fullName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                    Text(member.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Team Hours")
            .onAppear {
                if let managerId = authService.currentUser?.id {
                    fetchTeamMembers(managerId: managerId)
                }
            }
            .sheet(item: $selectedUser) { user in
                UserHoursSheet(user: user)
            }
        }
    }
    
    func fetchTeamMembers(managerId: String) {
        let db = Firestore.firestore()
        db.collection("users")
            .whereField("managerId", isEqualTo: managerId)
            .getDocuments { snapshot, error in
                isLoading = false
                guard let docs = snapshot?.documents else { return }
                teamMembers = docs.compactMap { doc in
                    let data = doc.data()
                    return MCUser(
                        id: doc.documentID,
                        email: data["email"] as? String ?? "",
                        firstName: data["firstName"] as? String ?? "",
                        lastName: data["lastName"] as? String ?? "",
                        role: UserRole(rawValue: data["role"] as? String ?? "employee") ?? .employee,
                        workspaceId: data["workspaceId"] as? String ?? "",
                        managerId: data["managerId"] as? String,
                        profileImageURL: data["profileImageURL"] as? String,
                        isActive: data["isActive"] as? Bool ?? true
                    )
                }
            }
    }
}

struct UserHoursSheet: View {
    var user: MCUser
    @State private var records: [DayRecord] = []
    @State private var isLoading = true
    @State private var selectedRecord: DayRecord?
    @State private var showCorrection = false
    @State private var correctionHours = 0
    @State private var correctionMinutes = 0
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if records.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No records")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        ForEach(records) { day in
                            DayRowView(day: day, showCorrectButton: true) {
                                selectedRecord = day
                                // Pretvori postojece sate u h i min
                                let totalHours = day.correctedHours ?? day.totalHours
                                correctionHours = Int(totalHours)
                                correctionMinutes = Int((totalHours - Double(Int(totalHours))) * 60)
                                showCorrection = true
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(user.fullName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                fetchRecords(userId: user.id)
            }
            .sheet(isPresented: $showCorrection) {
                CorrectionSheet(
                    date: selectedRecord?.displayDate ?? "",
                    hours: $correctionHours,
                    minutes: $correctionMinutes
                ) {
                    if let record = selectedRecord {
                        let totalHours = Double(correctionHours) + Double(correctionMinutes) / 60.0
                        saveCorrection(record: record, hours: totalHours)
                    }
                    showCorrection = false
                }
            }
        }
    }
    
    func fetchRecords(userId: String) {
        let db = Firestore.firestore()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        
        db.collection("clockEvents")
            .whereField("userId", isEqualTo: userId)
            .getDocuments { snapshot, error in
                isLoading = false
                guard let docs = snapshot?.documents else { return }
                
                var eventsByDay: [String: [ClockEvent]] = [:]
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                
                for doc in docs {
                    let data = doc.data()
                    let ts = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                    guard ts >= thirtyDaysAgo else { continue }
                    let event = ClockEvent(
                        id: doc.documentID,
                        userId: data["userId"] as? String ?? "",
                        workspaceId: data["workspaceId"] as? String ?? "",
                        type: ClockEventType(rawValue: data["type"] as? String ?? "clockIn") ?? .clockIn,
                        timestamp: ts,
                        locationId: data["locationId"] as? String ?? "",
                        overtimeNote: data["overtimeNote"] as? String,
                        isOvertimeApproved: data["isOvertimeApproved"] as? Bool,
                        managerNote: data["managerNote"] as? String,
                        correctedHours: data["correctedHours"] as? Double
                    )
                    let key = formatter.string(from: event.timestamp)
                    eventsByDay[key, default: []].append(event)
                }
                
                records = eventsByDay.map { key, dayEvents in
                    DayRecord(date: key, events: dayEvents.sorted { $0.timestamp < $1.timestamp })
                }.sorted { $0.date > $1.date }
            }
    }
    
    func saveCorrection(record: DayRecord, hours: Double) {
        let db = Firestore.firestore()
        guard let firstEvent = record.events.first else { return }
        
        db.collection("clockEvents").document(firstEvent.id).updateData([
            "correctedHours": hours
        ]) { error in
            if error == nil {
                fetchRecords(userId: user.id)
            }
        }
    }
}

struct CorrectionSheet: View {
    var date: String
    @Binding var hours: Int
    @Binding var minutes: Int
    var onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    Text(date)
                        .foregroundStyle(.secondary)
                }
                
                Section("Corrected Hours") {
                    HStack(spacing: 16) {
                        VStack(spacing: 8) {
                            Text("Hours")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Hours", selection: $hours) {
                                ForEach(0..<24) { h in
                                    Text("\(h)h").tag(h)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 100)
                        }
                        
                        VStack(spacing: 8) {
                            Text("Minutes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Minutes", selection: $minutes) {
                                ForEach([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], id: \.self) { m in
                                    Text("\(m)m").tag(m)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 100)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Correct Hours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
