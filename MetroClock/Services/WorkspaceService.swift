import Foundation
import FirebaseFirestore
import CoreLocation

struct MCOffice: Identifiable {
    let id: String
    var name: String
    var ssid: String
    var gpsLat: Double?
    var gpsLng: Double?
    var gpsRadius: Double
}

struct WorkspaceConfig {
    var clickupApiToken: String?
    var clickupUserMappings: [String: String]   // metroClockUserId → clickupUserId
    var slackWebhookUrl: String?
    var discordWebhookUrl: String?
    var slackUserMappings: [String: String]
    var discordUserMappings: [String: String]

    var hasClickUp: Bool { clickupApiToken != nil }

    init() {
        clickupApiToken = nil
        clickupUserMappings = [:]
        slackWebhookUrl = nil
        discordWebhookUrl = nil
        slackUserMappings = [:]
        discordUserMappings = [:]
    }
}

@Observable
class WorkspaceService: NSObject, CLLocationManagerDelegate {
    var offices: [MCOffice] = []
    var config: WorkspaceConfig = WorkspaceConfig()
    var currentLocation: CLLocation?
    var nearestOffice: MCOffice? = nil
    var isInOfficeZone: Bool = false
    var locationAuthStatus: CLAuthorizationStatus = .notDetermined

    private let db = Firestore.firestore()
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    // MARK: - Workspace Config

    func fetchWorkspaceConfig(workspaceId: String) {
        db.collection("workspaces").document(workspaceId).getDocument { [weak self] snapshot, error in
            guard let self = self, let data = snapshot?.data() else { return }
            var cfg = WorkspaceConfig()
            cfg.clickupApiToken = data["clickupApiToken"] as? String
            cfg.slackWebhookUrl = data["slackWebhookUrl"] as? String
            cfg.discordWebhookUrl = data["discordWebhookUrl"] as? String
            if let m = data["clickupUserMappings"] as? [String: String] { cfg.clickupUserMappings = m }
            if let m = data["slackUserMappings"] as? [String: String] { cfg.slackUserMappings = m }
            if let m = data["discordUserMappings"] as? [String: String] { cfg.discordUserMappings = m }
            self.config = cfg
        }
    }

    // Returns the ClickUp user ID for a given MetroClock user ID
    func clickupUserId(for metroUserId: String) -> String? {
        config.clickupUserMappings[metroUserId]
    }

    // MARK: - Offices

    func fetchOffices(workspaceId: String) {
        db.collection("offices")
            .whereField("workspaceId", isEqualTo: workspaceId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let docs = snapshot?.documents else { return }
                self.offices = docs.compactMap { doc in
                    let d = doc.data()
                    return MCOffice(
                        id: doc.documentID,
                        name: d["name"] as? String ?? "",
                        ssid: d["ssid"] as? String ?? "",
                        gpsLat: d["gpsLat"] as? Double,
                        gpsLng: d["gpsLng"] as? Double,
                        gpsRadius: d["gpsRadius"] as? Double ?? 100
                    )
                }
                self.startLocationUpdates()
                self.checkIfInOfficeZone()
            }
    }

    // MARK: - Location

    func startLocationUpdates() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationAuthStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        checkIfInOfficeZone()
    }

    private func checkIfInOfficeZone() {
        guard let currentLocation else {
            isInOfficeZone = false
            nearestOffice = nil
            return
        }
        for office in offices {
            guard let lat = office.gpsLat, let lng = office.gpsLng else { continue }
            let officeLocation = CLLocation(latitude: lat, longitude: lng)
            if currentLocation.distance(from: officeLocation) <= office.gpsRadius {
                isInOfficeZone = true
                nearestOffice = office
                return
            }
        }
        isInOfficeZone = false
        nearestOffice = nil
    }

    func isOnOfficeWiFi(ssid: String) -> Bool {
        return !ssid.isEmpty
    }
}
