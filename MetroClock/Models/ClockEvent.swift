import Foundation

enum ClockEventType: String, Codable {
    case clockIn
    case clockOut
}

struct ClockEvent: Codable, Identifiable {
    var id: String
    var userId: String
    var workspaceId: String
    var type: ClockEventType
    var timestamp: Date
    var locationId: String
    var overtimeNote: String?
    var isOvertimeApproved: Bool?
    var managerNote: String?
    var correctedHours: Double?
}
