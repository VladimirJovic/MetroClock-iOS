import Foundation

enum UserRole: String, Codable {
    case admin
    case manager
    case employee
}

struct MCUser: Codable, Identifiable {
    var id: String
    var email: String
    var firstName: String
    var lastName: String
    var role: UserRole
    var workspaceId: String
    var managerId: String?
    var isActive: Bool

    // Schedule
    var workDays: [Int]?
    var dailyHours: [String: Double]?
    var hourlyRate: Double?
    var currency: String?
    var overtimeMultiplier: Double?

    var fullName: String {
        "\(firstName) \(lastName)"
    }
}
