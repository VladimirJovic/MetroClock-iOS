import Foundation

enum RequestType: String, Codable {
    case remoteWork
    case sickLeave
    case dayOff
    case overtime
}

enum RequestStatus: String, Codable {
    case pending
    case approved
    case rejected
}

struct Request: Codable, Identifiable {
    var id: String
    var userId: String
    var workspaceId: String
    var managerId: String
    var type: RequestType
    var status: RequestStatus
    var date: Date
    var employeeNote: String?
    var managerNote: String?
    var createdAt: Date
    var remoteHours: Double?
}
