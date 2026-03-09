import Foundation
import FirebaseAuth
import FirebaseFirestore

@Observable
class AuthService {
    var currentUser: MCUser?
    var isAuthenticated: Bool = false
    var isLoading: Bool = false
    var errorMessage: String?

    private let db = Firestore.firestore()

    init() {
        checkCurrentUser()
    }

    func checkCurrentUser() {
        guard let firebaseUser = Auth.auth().currentUser else {
            isAuthenticated = false
            return
        }
        fetchUser(uid: firebaseUser.uid)
    }

    func login(email: String, password: String) {
        isLoading = true
        errorMessage = nil
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            guard let self = self else { return }
            self.isLoading = false
            if let error = error {
                self.errorMessage = error.localizedDescription
                return
            }
            guard let uid = result?.user.uid else { return }
            self.fetchUser(uid: uid)
        }
    }

    func logout() {
        try? Auth.auth().signOut()
        currentUser = nil
        isAuthenticated = false
    }

    private func fetchUser(uid: String) {
        db.collection("users").document(uid).getDocument { [weak self] snapshot, error in
            guard let self = self else { return }
            guard let data = snapshot?.data() else {
                self.errorMessage = "User not found"
                self.isAuthenticated = false
                return
            }

            // dailyHours: {"0": 0, "1": 8, ...}
            var dailyHours: [String: Double]? = nil
            if let raw = data["dailyHours"] as? [String: Any] {
                var parsed: [String: Double] = [:]
                for (key, val) in raw {
                    if let d = val as? Double {
                        parsed[key] = d
                    } else if let l = val as? Int {
                        parsed[key] = Double(l)
                    }
                }
                dailyHours = parsed
            }

            // workDays: [1,2,3,4,5]
            var workDays: [Int]? = nil
            if let raw = data["workDays"] as? [Any] {
                workDays = raw.compactMap {
                    if let i = $0 as? Int { return i }
                    if let l = $0 as? Int64 { return Int(l) }
                    return nil
                }
            }

            let hourlyRate = (data["hourlyRate"] as? Double) ?? (data["hourlyRate"] as? Int).map { Double($0) }
            let overtimeMultiplier = (data["overtimeMultiplier"] as? Double) ?? (data["overtimeMultiplier"] as? Int).map { Double($0) }

            let user = MCUser(
                id: data["id"] as? String ?? uid,
                email: data["email"] as? String ?? "",
                firstName: data["firstName"] as? String ?? "",
                lastName: data["lastName"] as? String ?? "",
                role: UserRole(rawValue: data["role"] as? String ?? "employee") ?? .employee,
                workspaceId: data["workspaceId"] as? String ?? "",
                managerId: data["managerId"] as? String,
                profileImageURL: data["profileImageURL"] as? String,
                isActive: data["isActive"] as? Bool ?? true,
                workDays: workDays,
                dailyHours: dailyHours,
                hourlyRate: hourlyRate,
                currency: data["currency"] as? String,
                overtimeMultiplier: overtimeMultiplier
            )

            guard user.isActive else {
                try? Auth.auth().signOut()
                self.errorMessage = "Your account has been deactivated. Contact your administrator."
                self.isAuthenticated = false
                return
            }

            self.currentUser = user
            self.isAuthenticated = true
        }
    }
}
