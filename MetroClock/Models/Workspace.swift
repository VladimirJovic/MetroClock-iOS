import Foundation

struct Workspace: Codable, Identifiable {
    var id: String
    var name: String
    var adminId: String
    var locations: [Location]
}

struct Location: Codable, Identifiable {
    var id: String
    var name: String
    var ssid: String
    var workspaceId: String
}
