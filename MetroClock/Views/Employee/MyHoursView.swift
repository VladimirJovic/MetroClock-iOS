import SwiftUI
import FirebaseFirestore

struct MyHoursView: View {
    @Environment(AuthService.self) var authService
    @State private var records: [DayRecord] = []
    @State private var isLoading = true
    
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
                        Text("No records yet")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        ForEach(records) { day in
                            DayRowView(day: day)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("My Hours")
            .onAppear {
                if let userId = authService.currentUser?.id {
                    fetchRecords(userId: userId)
                }
            }
        }
    }
    
    func fetchRecords(userId: String) {
        let db = Firestore.firestore()
        
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
                    let event = ClockEvent(
                        id: doc.documentID,
                        userId: data["userId"] as? String ?? "",
                        workspaceId: data["workspaceId"] as? String ?? "",
                        type: ClockEventType(rawValue: data["type"] as? String ?? "clockIn") ?? .clockIn,
                        timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
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
}

struct DayRecord: Identifiable {
    var id: String { date }
    var date: String
    var events: [ClockEvent]
    
    var totalHours: Double {
        var total: Double = 0
        var lastClockIn: Date?
        for event in events {
            if event.type == .clockIn {
                lastClockIn = event.timestamp
            } else if event.type == .clockOut, let clockIn = lastClockIn {
                total += event.timestamp.timeIntervalSince(clockIn) / 3600
                lastClockIn = nil
            }
        }
        if let clockIn = lastClockIn {
            total += Date().timeIntervalSince(clockIn) / 3600
        }
        return total
    }
    
    var correctedHours: Double? {
        events.first?.correctedHours
    }
    
    var displayHours: Double {
        correctedHours ?? totalHours
    }
    
    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: date) else { return self.date }
        let display = DateFormatter()
        display.dateStyle = .full
        display.timeStyle = .none
        return display.string(from: date)
    }
    
    var hoursString: String {
        let h = Int(displayHours)
        let m = Int((displayHours - Double(h)) * 60)
        if correctedHours != nil {
            return "\(h)h \(m)m ✎"
        }
        return "\(h)h \(m)m"
    }
}

struct DayRowView: View {
    var day: DayRecord
    var showCorrectButton: Bool = false
    var onCorrect: (() -> Void)? = nil
    @State private var isExpanded = false
    
    var statusColor: Color {
        if day.totalHours >= 8 { return .green }
        if day.totalHours >= 4 { return .orange }
        return .red
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.displayDate)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                    }
                    
                    Spacer()
                    
                    Text(day.hoursString)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.12))
                        .cornerRadius(8)
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.vertical, 8)
                    
                    ForEach(Array(day.events.enumerated()), id: \.element.id) { index, event in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(event.type == .clockIn ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                Image(systemName: event.type == .clockIn ? "arrow.right.circle.fill" : "arrow.left.circle.fill")
                                    .foregroundStyle(event.type == .clockIn ? .green : .red)
                                    .font(.system(size: 16))
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.type == .clockIn ? "Clocked In" : "Clocked Out")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if let note = event.overtimeNote {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            
                            Spacer()
                            
                            Text(event.timestamp, style: .time)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        
                        if index < day.events.count - 1 {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                    
                    if showCorrectButton, let onCorrect = onCorrect {
                        Divider()
                            .padding(.vertical, 8)
                        Button {
                            onCorrect()
                        } label: {
                            Label("Correct Hours", systemImage: "pencil")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.12))
                                .foregroundStyle(.blue)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
