import Foundation
import FirebaseFirestore

@Observable
class ClockService {
    var todayEvents: [ClockEvent] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var isClockedIn: Bool = false
    var lastClockIn: ClockEvent?

    private let db = Firestore.firestore()

    func fetchTodayEvents(userId: String) {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        db.collection("clockEvents")
            .whereField("userId", isEqualTo: userId)
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                let events: [ClockEvent] = snapshot?.documents.compactMap { doc in
                    let data = doc.data()
                    return ClockEvent(
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
                } ?? []
                self.todayEvents = events.sorted { $0.timestamp < $1.timestamp }
                self.lastClockIn = self.todayEvents.last(where: { $0.type == .clockIn })
                self.isClockedIn = self.todayEvents.last?.type == .clockIn
            }
    }

    func clockIn(userId: String, workspaceId: String, locationId: String, taskIds: [String]? = nil) {
        isLoading = true
        var event: [String: Any] = [
            "userId": userId,
            "workspaceId": workspaceId,
            "type": "clockIn",
            "timestamp": Timestamp(date: Date()),
            "locationId": locationId
        ]
        if let taskIds = taskIds, !taskIds.isEmpty {
            event["taskIds"] = taskIds
        }
        db.collection("clockEvents").addDocument(data: event) { [weak self] error in
            guard let self = self else { return }
            self.isLoading = false
            if let error = error {
                self.errorMessage = "Failed to clock in. Please check your connection and try again."
                print("Clock in error: \(error.localizedDescription)")
            } else {
                self.fetchTodayEvents(userId: userId)
            }
        }
    }

    func clockOut(userId: String, workspaceId: String, locationId: String,
                  overtimeNote: String? = nil, managerId: String? = nil,
                  plannedHours: Double = 8) {
        isLoading = true
        let officeHours = calculateOfficeHoursToNow()

        fetchApprovedRemoteHoursToday(userId: userId, workspaceId: workspaceId) { [weak self] remoteHours in
            guard let self = self else { return }

            let totalHours = officeHours + remoteHours
            let isOvertime = totalHours > plannedHours
            let overtimeAmount = totalHours - plannedHours

            var event: [String: Any] = [
                "userId": userId,
                "workspaceId": workspaceId,
                "type": "clockOut",
                "timestamp": Timestamp(date: Date()),
                "locationId": locationId
            ]
            if let note = overtimeNote {
                event["overtimeNote"] = note
            }

            self.db.collection("clockEvents").addDocument(data: event) { error in
                self.isLoading = false
                if let error = error {
                    self.errorMessage = "Failed to clock out. Please check your connection and try again."
                    print("Clock out error: \(error.localizedDescription)")
                    return
                }
                if isOvertime, let managerId = managerId, let note = overtimeNote {
                    let request: [String: Any] = [
                        "userId": userId,
                        "workspaceId": workspaceId,
                        "managerId": managerId,
                        "type": "overtime",
                        "status": "pending",
                        "date": Timestamp(date: Date()),
                        "employeeNote": note,
                        "overtimeHours": overtimeAmount,
                        "createdAt": Timestamp(date: Date())
                    ]
                    self.db.collection("requests").addDocument(data: request) { err in
                        if let err = err {
                            print("Overtime request failed: \(err.localizedDescription)")
                        }
                    }
                }
                self.fetchTodayEvents(userId: userId)
            }
        }
    }

    func checkOvertimeBeforeClockOut(userId: String, workspaceId: String, plannedHours: Double, completion: @escaping (Bool) -> Void) {
        let officeHours = calculateOfficeHoursToNow()
        fetchApprovedRemoteHoursToday(userId: userId, workspaceId: workspaceId) { remoteHours in
            completion(officeHours + remoteHours > plannedHours)
        }
    }

    func calculateOfficeHoursToNow() -> Double {
        var total = 0.0
        var lastIn: Date? = nil
        for event in todayEvents.sorted(by: { $0.timestamp < $1.timestamp }) {
            if event.type == .clockIn  { lastIn = event.timestamp }
            if event.type == .clockOut, let ci = lastIn {
                total += event.timestamp.timeIntervalSince(ci) / 3600
                lastIn = nil
            }
        }
        if let ci = lastIn {
            total += Date().timeIntervalSince(ci) / 3600
        }
        return total
    }

    func fetchApprovedRemoteHoursToday(userId: String, workspaceId: String, completion: @escaping (Double) -> Void) {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        db.collection("requests")
            .whereField("userId", isEqualTo: userId)
            .whereField("type", isEqualTo: "remoteWork")
            .whereField("status", isEqualTo: "approved")
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .whereField("date", isLessThan: Timestamp(date: endOfDay))
            .getDocuments { snapshot, _ in
                let total = snapshot?.documents.reduce(0.0) { sum, doc in
                    sum + (doc.data()["remoteHours"] as? Double ?? 0)
                } ?? 0
                completion(total)
            }
    }
}
