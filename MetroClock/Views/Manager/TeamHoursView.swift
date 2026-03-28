import SwiftUI
import FirebaseFirestore

// MARK: - RemoteEntry
struct RemoteEntry: Identifiable {
    var id: String; var hours: Double; var note: String?
}

// MARK: - DayRecordWithRemote
struct DayRecordWithRemote: Identifiable {
    var id: String { date }
    var date: String; var events: [ClockEvent]; var remoteEntries: [RemoteEntry]
    var officeHours: Double {
        var total: Double = 0; var lastIn: Date? = nil
        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            if event.type == .clockIn  { lastIn = event.timestamp }
            if event.type == .clockOut, let ci = lastIn { total += event.timestamp.timeIntervalSince(ci) / 3600; lastIn = nil }
        }
        if let ci = lastIn { total += Date().timeIntervalSince(ci) / 3600 }
        return total
    }
    var totalRemoteHours: Double { remoteEntries.reduce(0) { $0 + $1.hours } }
    var totalHours: Double { officeHours + totalRemoteHours }
    var displayDate: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: date) else { return date }
        let g = DateFormatter(); g.dateStyle = .full; g.timeStyle = .none
        return g.string(from: d)
    }
    var hoursString: String { let h = Int(totalHours); let m = Int((totalHours - Double(h)) * 60); return "\(h)h \(m)m" }
    /// Work type label for the day header chip
    var workType: String? {
        let hasOffice = events.contains { $0.type == .clockIn }
        let hasRemote = !remoteEntries.isEmpty
        if hasOffice && hasRemote { return "Hybrid" }
        if hasRemote              { return "Remote" }
        return nil
    }
}

// MARK: - TeamHoursView
struct TeamHoursView: View {
    @Environment(AuthService.self) var authService
    @Environment(BadgeService.self) var badgeService
    @State private var teamMembers: [MCUser] = []
    @State private var selectedUser: MCUser?
    @State private var isLoading = true
    var body: some View {
        NavigationStack {
            ZStack { Color.mcBackground.ignoresSafeArea()
                Group {
                    if isLoading { ProgressView().tint(Color.mcOrange) }
                    else if teamMembers.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.3").font(.system(size: 48)).foregroundStyle(Color.mcTextTertiary)
                            Text("No team members").foregroundStyle(Color.mcTextSecondary)
                        }
                    } else {
                        List(teamMembers) { member in
                        Button { selectedUser = member } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(Color.mcOrange.opacity(0.12)).frame(width: 40, height: 40)
                                    Text(member.firstName.prefix(1) + member.lastName.prefix(1)).font(.subheadline).fontWeight(.semibold).foregroundStyle(Color.mcOrange)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(member.fullName).font(.subheadline).fontWeight(.medium).foregroundStyle(.primary)
                                    // Alert pills — shown below name, only when there's an issue
                                    let hasPending  = badgeService.pendingRequestUserIds.contains(member.id)
                                    let hasOpen     = badgeService.openSessionUserIds.contains(member.id)
                                    let hasOvertime = badgeService.pendingOvertimeUserIds.contains(member.id)
                                    if hasPending || hasOpen || hasOvertime {
                                        HStack(spacing: 4) {
                                            if hasOpen    { Circle().fill(Color.red).frame(width: 8, height: 8) }
                                            if hasPending { Circle().fill(Color.mcOrange).frame(width: 8, height: 8) }
                                            if hasOvertime { Circle().fill(Color(hex: "B07800")).frame(width: 8, height: 8) }
                                        }
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }.buttonStyle(.plain)
                        }.listStyle(.insetGrouped).scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Team Hours")
            .onAppear { if let id = authService.currentUser?.id { fetchTeamMembers(managerId: id) } }
            .sheet(item: $selectedUser) { user in UserHoursSheet(user: user) }
        }
    }
    func fetchTeamMembers(managerId: String) {
        Firestore.firestore().collection("users").whereField("managerId", isEqualTo: managerId).getDocuments { snapshot, _ in
            isLoading = false
            teamMembers = snapshot?.documents.compactMap { doc in
                let d = doc.data()
                return MCUser(id: doc.documentID, email: d["email"] as? String ?? "", firstName: d["firstName"] as? String ?? "", lastName: d["lastName"] as? String ?? "", role: UserRole(rawValue: d["role"] as? String ?? "employee") ?? .employee, workspaceId: d["workspaceId"] as? String ?? "", managerId: d["managerId"] as? String, isActive: d["isActive"] as? Bool ?? true)
            } ?? []
        }
    }
}

// MARK: - UserHoursSheet
struct UserHoursSheet: View {
    var user: MCUser
    @State private var records: [DayRecordWithRemote] = []
    @State private var isLoading = true
    @State private var editingEvent: ClockEvent? = nil
    @State private var addingEventType: ClockEventType? = nil
    @State private var addingForRecord: DayRecordWithRemote? = nil
    @State private var selectedTime: Date = Date()
    @State private var showEditEventSheet = false
    @State private var validationError: String? = nil
    @State private var deletingEvent: ClockEvent? = nil
    @State private var showDeleteAlert = false
    @State private var editingRemoteEntry: RemoteEntry? = nil
    @State private var remoteHoursValue: Double = 1.0
    @State private var showEditRemoteSheet = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading { ProgressView() }
                else if records.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock").font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("No records").foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        ForEach(records) { day in
                            ManagerDayRowView(
                                day: day,
                                onEditEvent: { event in
                                    editingEvent = event; addingEventType = nil; addingForRecord = nil
                                    selectedTime = event.timestamp; validationError = nil; showEditEventSheet = true
                                },
                                onDeleteEvent: { event in deletingEvent = event; showDeleteAlert = true },
                                onAddEvent: { type in
                                    addingEventType = type; addingForRecord = day; editingEvent = nil
                                    let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
                                    if type == .clockOut,
                                       let lastIn = day.events.filter({ $0.type == .clockIn }).sorted(by: { $0.timestamp < $1.timestamp }).last?.timestamp {
                                        selectedTime = lastIn.addingTimeInterval(60)
                                    } else if let d = fmt.date(from: day.date) {
                                        selectedTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
                                    }
                                    validationError = nil; showEditEventSheet = true
                                },
                                onEditRemote: { entry in editingRemoteEntry = entry; remoteHoursValue = entry.hours; showEditRemoteSheet = true }
                            )
                        }
                    }.listStyle(.insetGrouped)
                }
            }
            .navigationTitle(user.fullName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .onAppear { fetchRecords(userId: user.id) }
            .sheet(isPresented: $showEditEventSheet) {
                EditEventSheet(title: eventSheetTitle, selectedTime: $selectedTime, validationError: validationError) { handleEventSave() }
            }
            .sheet(isPresented: $showEditRemoteSheet) {
                EditRemoteHoursSheet(hours: $remoteHoursValue) { handleRemoteSave() }
            }
            .alert("Delete Event?", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { deletingEvent = nil }
                Button("Delete", role: .destructive) {
                    if let event = deletingEvent { deleteEvent(eventId: event.id) }
                    deletingEvent = nil
                }
            } message: {
                if let event = deletingEvent {
                    Text("Delete \(event.type == .clockIn ? "Clock In" : "Clock Out") at \(event.timestamp.formatted(date: .omitted, time: .shortened))?")
                }
            }
        }
    }

    var eventSheetTitle: String {
        if let e = editingEvent { return e.type == .clockIn ? "Edit Clock In" : "Edit Clock Out" }
        if let t = addingEventType { return t == .clockIn ? "Add Clock In" : "Add Clock Out" }
        return "Edit Time"
    }

    func handleEventSave() {
        if let event = editingEvent {
            guard let record = records.first(where: { $0.events.contains(where: { $0.id == event.id }) }) else { return }
            if let error = validateTime(selectedTime, forEvent: event, inRecord: record) { validationError = error; showEditEventSheet = true; return }
            updateEventTimestamp(eventId: event.id, newTime: selectedTime)
        } else if let type = addingEventType, let record = addingForRecord {
            if let error = validateNewEvent(type: type, time: selectedTime, inRecord: record) { validationError = error; showEditEventSheet = true; return }
            addEvent(type: type, time: selectedTime, record: record)
        }
        showEditEventSheet = false; validationError = nil
    }

    func validateTime(_ newTime: Date, forEvent event: ClockEvent, inRecord record: DayRecordWithRemote) -> String? {
        let others = record.events.filter { $0.id != event.id }.sorted { $0.timestamp < $1.timestamp }
        for other in others {
            if Calendar.current.isDate(newTime, equalTo: other.timestamp, toGranularity: .minute) { return "Time conflicts with another event" }
            if event.type == .clockIn && other.type == .clockOut && isPaired(clockIn: event, clockOut: other, in: record) { if newTime >= other.timestamp { return "Clock In must be before Clock Out" } }
            if event.type == .clockOut && other.type == .clockIn && isPaired(clockIn: other, clockOut: event, in: record) { if newTime <= other.timestamp { return "Clock Out must be after Clock In" } }
        }
        return nil
    }

    func isPaired(clockIn: ClockEvent, clockOut: ClockEvent, in record: DayRecordWithRemote) -> Bool {
        let sorted = record.events.sorted { $0.timestamp < $1.timestamp }
        guard let i = sorted.firstIndex(where: { $0.id == clockIn.id }), let o = sorted.firstIndex(where: { $0.id == clockOut.id }) else { return false }
        return o == i + 1
    }

    func validateNewEvent(type: ClockEventType, time: Date, inRecord record: DayRecordWithRemote) -> String? {
        for e in record.events { if Calendar.current.isDate(time, equalTo: e.timestamp, toGranularity: .minute) { return "Time conflicts with an existing event" } }
        if type == .clockOut { if let lastIn = record.events.filter({ $0.type == .clockIn }).max(by: { $0.timestamp < $1.timestamp }), time <= lastIn.timestamp { return "Clock Out must be after Clock In" } }
        if type == .clockIn { if let firstOut = record.events.filter({ $0.type == .clockOut }).min(by: { $0.timestamp < $1.timestamp }), time >= firstOut.timestamp { return "Clock In must be before Clock Out" } }
        return nil
    }

    func updateEventTimestamp(eventId: String, newTime: Date) {
        Firestore.firestore().collection("clockEvents").document(eventId).updateData(["timestamp": Timestamp(date: newTime)]) { error in
            if error == nil { fetchRecords(userId: user.id) }
        }
    }

    func deleteEvent(eventId: String) {
        Firestore.firestore().collection("clockEvents").document(eventId).delete { error in
            if error == nil { fetchRecords(userId: user.id) }
        }
    }

    func addEvent(type: ClockEventType, time: Date, record: DayRecordWithRemote) {
        let data: [String: Any] = ["userId": user.id, "workspaceId": record.events.first?.workspaceId ?? user.workspaceId, "type": type.rawValue, "timestamp": Timestamp(date: time), "locationId": "manual"]
        Firestore.firestore().collection("clockEvents").addDocument(data: data) { error in if error == nil { fetchRecords(userId: user.id) } }
    }

    func handleRemoteSave() {
        guard let entry = editingRemoteEntry else { return }
        Firestore.firestore().collection("requests").document(entry.id).updateData(["remoteHours": remoteHoursValue]) { error in if error == nil { fetchRecords(userId: user.id) } }
        showEditRemoteSheet = false
    }

    func fetchRecords(userId: String) {
        let db = Firestore.firestore()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        db.collection("clockEvents").whereField("userId", isEqualTo: userId).getDocuments { snapshot, _ in
            var eventsByDay: [String: [ClockEvent]] = [:]
            for doc in snapshot?.documents ?? [] {
                let d = doc.data(); let ts = (d["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                guard ts >= thirtyDaysAgo else { continue }
                let event = ClockEvent(id: doc.documentID, userId: d["userId"] as? String ?? "", workspaceId: d["workspaceId"] as? String ?? "", type: ClockEventType(rawValue: d["type"] as? String ?? "clockIn") ?? .clockIn, timestamp: ts, locationId: d["locationId"] as? String ?? "", overtimeNote: d["overtimeNote"] as? String, isOvertimeApproved: d["isOvertimeApproved"] as? Bool, managerNote: d["managerNote"] as? String, correctedHours: d["correctedHours"] as? Double)
                eventsByDay[fmt.string(from: ts), default: []].append(event)
            }
            db.collection("requests").whereField("userId", isEqualTo: userId).whereField("type", isEqualTo: "remoteWork").whereField("status", isEqualTo: "approved").getDocuments { reqSnapshot, _ in
                isLoading = false
                var remoteByDay: [String: [RemoteEntry]] = [:]
                for doc in reqSnapshot?.documents ?? [] {
                    let d = doc.data()
                    guard let ts = (d["date"] as? Timestamp)?.dateValue(), ts >= thirtyDaysAgo else { continue }
                    let hours: Double
                    if let dv = d["remoteHours"] as? Double { hours = dv } else if let lv = d["remoteHours"] as? Int { hours = Double(lv) } else { continue }
                    remoteByDay[fmt.string(from: ts), default: []].append(RemoteEntry(id: doc.documentID, hours: hours, note: d["employeeNote"] as? String))
                }
                var allDays: [String: DayRecordWithRemote] = [:]
                for (key, events) in eventsByDay { allDays[key] = DayRecordWithRemote(date: key, events: events.sorted { $0.timestamp < $1.timestamp }, remoteEntries: remoteByDay[key] ?? []) }
                for (key, entries) in remoteByDay where allDays[key] == nil { allDays[key] = DayRecordWithRemote(date: key, events: [], remoteEntries: entries) }
                records = allDays.values.sorted { $0.date > $1.date }
            }
        }
    }
}

// MARK: - ManagerDayRowView
struct ManagerDayRowView: View {
    var day: DayRecordWithRemote
    var onEditEvent: (ClockEvent) -> Void
    var onDeleteEvent: (ClockEvent) -> Void
    var onAddEvent: (ClockEventType) -> Void
    var onEditRemote: (RemoteEntry) -> Void
    @State private var isExpanded = false

    var statusColor: Color { day.totalHours >= 8 ? .green : day.totalHours >= 4 ? .orange : .red }
    var hasClockIn:  Bool { day.events.contains { $0.type == .clockIn } }
    var hasClockOut: Bool { day.events.contains { $0.type == .clockOut } }

    /// True if the last event of the day is a clockIn (open session — no matching clockOut)
    var hasUnpairedClockIn: Bool {
        var open = false
        for ev in day.events.sorted(by: { $0.timestamp < $1.timestamp }) {
            if ev.type == .clockIn  { open = true  }
            if ev.type == .clockOut { open = false }
        }
        return open
    }


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() } } label: {
                HStack(spacing: 8) {
                    Text(day.displayDate).font(.subheadline).fontWeight(.medium).foregroundStyle(.primary)
                    if hasUnpairedClockIn {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                    if let wt = day.workType {
                        let wtColor: Color = wt == "Hybrid" ? Color(red: 0.61, green: 0.40, blue: 0.89) : .teal
                        Text(wt)
                            .font(.caption2).fontWeight(.semibold)
                            .foregroundStyle(wtColor)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(wtColor.opacity(0.14))
                            .cornerRadius(4)
                    }
                    Spacer()
                    Text(day.hoursString).font(.subheadline).fontWeight(.semibold).foregroundStyle(statusColor).padding(.horizontal, 10).padding(.vertical, 4).background(statusColor.opacity(0.12)).cornerRadius(8)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }.buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    Divider().padding(.vertical, 8)
                    ForEach(Array(day.events.enumerated()), id: \.element.id) { index, event in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(event.type == .clockIn ? Color.green.opacity(0.15) : Color.red.opacity(0.15)).frame(width: 32, height: 32)
                                Image(systemName: event.type == .clockIn ? "arrow.right.circle.fill" : "arrow.left.circle.fill").foregroundStyle(event.type == .clockIn ? .green : .red).font(.system(size: 16))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.type == .clockIn ? "Clock In" : "Clock Out").font(.subheadline).fontWeight(.medium)
                                if event.locationId == "manual" { Text("Added manually").font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(event.timestamp, style: .time).font(.subheadline).foregroundStyle(.secondary)
                            Button { onEditEvent(event) } label: {
                                Image(systemName: "pencil").font(.caption).foregroundStyle(.blue).padding(6).background(Color.blue.opacity(0.1)).cornerRadius(6)
                            }.buttonStyle(.plain)
                            Button { onDeleteEvent(event) } label: {
                                Image(systemName: "trash").font(.caption).foregroundStyle(.red).padding(6).background(Color.red.opacity(0.1)).cornerRadius(6)
                            }.buttonStyle(.plain)
                        }.padding(.vertical, 6)
                        if index < day.events.count - 1 { Divider().padding(.leading, 44) }
                    }
                    if !day.remoteEntries.isEmpty {
                        if !day.events.isEmpty { Divider().padding(.vertical, 4) }
                        ForEach(day.remoteEntries) { entry in
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(Color.teal.opacity(0.15)).frame(width: 32, height: 32)
                                    Image(systemName: "house.fill").foregroundStyle(.teal).font(.system(size: 14))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Remote Work").font(.subheadline).fontWeight(.medium)
                                    if let note = entry.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                Spacer()
                                Text(entry.hours.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(entry.hours))h" : String(format: "%.1fh", entry.hours)).font(.subheadline).foregroundStyle(.secondary)
                                Button { onEditRemote(entry) } label: {
                                    Image(systemName: "pencil").font(.caption).foregroundStyle(.teal).padding(6).background(Color.teal.opacity(0.1)).cornerRadius(6)
                                }.buttonStyle(.plain)
                            }.padding(.vertical, 6)
                        }
                    }
                    let addButtons = missingEventTypes
                    if !addButtons.isEmpty {
                        Divider().padding(.vertical, 8)
                        HStack(spacing: 10) {
                            ForEach(addButtons, id: \.self) { type in
                                Button { onAddEvent(type) } label: {
                                    Label(type == .clockIn ? "Add Clock In" : "Add Clock Out", systemImage: "plus.circle").font(.caption).fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 8).background(type == .clockIn ? Color.green.opacity(0.1) : Color.red.opacity(0.1)).foregroundStyle(type == .clockIn ? .green : .red).cornerRadius(8)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }.padding(.vertical, 4)
    }
    var missingEventTypes: [ClockEventType] {
        var m: [ClockEventType] = []
        if !hasClockIn { m.append(.clockIn) }
        // Show "Add Clock Out" if there's no clockOut at all OR if there's an unpaired clockIn
        if !hasClockOut || hasUnpairedClockIn { m.append(.clockOut) }
        return m
    }
}

// MARK: - EditEventSheet
struct EditEventSheet: View {
    var title: String; @Binding var selectedTime: Date; var validationError: String?; var onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Time") { DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute).datePickerStyle(.wheel).labelsHidden() }
                if let error = validationError { Section { Text(error).foregroundStyle(.red).font(.caption) } }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Save") { onSave() }.fontWeight(.semibold) }
            }
        }.presentationDetents([.medium])
    }
}

// MARK: - EditRemoteHoursSheet
struct EditRemoteHoursSheet: View {
    @Binding var hours: Double; var onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    let options: [Double] = stride(from: 0.5, through: 24.0, by: 0.5).map { $0 }
    var body: some View {
        NavigationStack {
            Form {
                Section("Remote Hours") {
                    Picker("Hours", selection: $hours) {
                        ForEach(options, id: \.self) { h in Text(h.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(h))h" : String(format: "%.1fh", h)).tag(h) }
                    }.pickerStyle(.wheel)
                }
            }
            .navigationTitle("Edit Remote Hours").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Save") { onSave() }.fontWeight(.semibold) }
            }
        }.presentationDetents([.medium])
    }
}
