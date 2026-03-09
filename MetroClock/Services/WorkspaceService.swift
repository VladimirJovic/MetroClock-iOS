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

@Observable
class WorkspaceService: NSObject, CLLocationManagerDelegate {
    var offices: [MCOffice] = []
    var currentLocation: CLLocation?
    var nearestOffice: MCOffice? = nil   // office user is currently inside GPS zone of
    var isInOfficeZone: Bool = false
    var locationAuthStatus: CLAuthorizationStatus = .notDetermined

    private let db = Firestore.firestore()
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

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

    // Call this to check WiFi match for a given office SSID
    func isOnOfficeWiFi(ssid: String) -> Bool {
        // WiFiService will handle actual SSID check — this is just helper
        return !ssid.isEmpty
    }
}
