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
    var date: Date           // = dateFrom, kept for backwards compatibility
    var dateFrom: Date       // start of range
    var dateTo: Date         // end of range (same as dateFrom for single-day)
    var employeeNote: String?
    var managerNote: String?
    var createdAt: Date
    var remoteHours: Double?  // only for remoteWork

    // All dates covered by this request
    var allDates: [Date] {
        var dates: [Date] = []
        var current = Calendar.current.startOfDay(for: dateFrom)
        let end = Calendar.current.startOfDay(for: dateTo)
        while current <= end {
            dates.append(current)
            current = Calendar.current.date(byAdding: .day, value: 1, to: current)!
        }
        return dates
    }

    var isRange: Bool {
        !Calendar.current.isDate(dateFrom, inSameDayAs: dateTo)
    }

    var dateRangeLabel: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        if isRange {
            return "\(fmt.string(from: dateFrom)) – \(fmt.string(from: dateTo))"
        }
        return fmt.string(from: dateFrom)
    }

    // Check if a given date falls within this request's range
    func contains(date: Date) -> Bool {
        let cal = Calendar.current
        let d = cal.startOfDay(for: date)
        let from = cal.startOfDay(for: dateFrom)
        let to = cal.startOfDay(for: dateTo)
        return d >= from && d <= to
    }
}
