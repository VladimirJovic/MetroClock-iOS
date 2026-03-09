import Foundation
import SystemConfiguration.CaptiveNetwork
import CoreLocation

@Observable
class WiFiService: NSObject, CLLocationManagerDelegate {
    var currentSSID: String?
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
    }
    
    func getCurrentSSID() {
        if let interfaces = CNCopySupportedInterfaces() as? [String] {
            for interface in interfaces {
                if let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: Any] {
                    currentSSID = info[kCNNetworkInfoKeySSID as String] as? String
                    return
                }
            }
        }
        currentSSID = nil
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        getCurrentSSID()
    }
}
