import Foundation
import FirebaseFirestore

/// Tracks unread/actionable counts for tab-bar badges and per-employee indicators.
@Observable
final class BadgeService {

    // MARK: - Public state

    /// Badge on manager's Team tab = open sessions + pending overtime
    var managerTeamBadgeCount: Int = 0

    /// Badge on manager's Inbox tab = pending approval requests only
    var managerInboxBadgeCount: Int = 0

    /// Badge on employee's Requests tab = resolved requests not yet seen
    var employeeBadgeCount: Int = 0

    /// Per-employee sets for TeamHoursView indicators
    var pendingRequestUserIds:  Set<String> = []
    var openSessionUserIds:     Set<String> = []
    var openSessionDates:       [String: Date] = [:]   // userId → date of the open clockIn
    var pendingOvertimeUserIds: Set<String> = []

    // MARK: - Private

    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []

    deinit { stopListening() }

    // MARK: - Public API

    func startListening(for user: MCUser) {
        stopListening()
        switch user.role {
        case .manager:
            listenForDirectReports(managerId: user.id, workspaceId: user.workspaceId)
        case .employee:
            listenForResolvedRequests(userId: user.id)
        case .admin:
            break
        }
    }

    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners = []
    }

    /// Call this when the employee opens the Requests tab so the badge resets.
    func markAllResolvedAsSeen(ids: [String]) {
        guard !ids.isEmpty else { return }
        var seen = seenResolvedIds
        seen.formUnion(ids)
        seenResolvedIds = seen
        employeeBadgeCount = 0
    }

    // MARK: - Manager listeners

    private func listenForDirectReports(managerId: String, workspaceId: String) {
        let l = db.collection("users")
            .whereField("managerId", isEqualTo: managerId)
            .whereField("isActive", isEqualTo: true)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let snap else { return }
                let ids = snap.documents.map { $0.documentID }
                self.listenForPendingRequests(managerId: managerId, reportIds: ids)
                self.listenOpenSessions(reportIds: ids, workspaceId: workspaceId)
                self.listenPendingOvertime(reportIds: ids, workspaceId: workspaceId)
            }
        listeners.append(l)
    }

    private func listenForPendingRequests(managerId: String, reportIds: [String]) {
        guard !reportIds.isEmpty else {
            pendingRequestUserIds = []
            recomputeManagerBadge()
            return
        }
        let l = db.collection("requests")
            .whereField("managerId", isEqualTo: managerId)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let snap else { return }
                self.pendingRequestUserIds = Set(
                    snap.documents.compactMap { $0.data()["userId"] as? String }
                )
                self.recomputeManagerBadge()
            }
        listeners.append(l)
    }

    /// Real-time listener: direct reports whose last clockIn is from a previous day with no matching clockOut.
    private func listenOpenSessions(reportIds: [String], workspaceId: String) {
        guard !reportIds.isEmpty else {
            openSessionUserIds = []; openSessionDates = [:]; recomputeManagerBadge(); return
        }
        let cal = Calendar.current
        let yesterdayStart = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: Date())!)
        let todayStart     = cal.startOfDay(for: Date())

        let chunks = stride(from: 0, to: reportIds.count, by: 30)
            .map { Array(reportIds[$0 ..< min($0 + 30, reportIds.count)]) }

        // One slot per chunk; all closures share this array via Swift's capture-by-reference
        var chunkEvents = (0 ..< chunks.count).map { _ in [String: [(type: ClockEventType, ts: Date)]]() }

        for (i, chunk) in chunks.enumerated() {
            let l = db.collection("clockEvents")
                .whereField("userId", in: chunk)
                .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: yesterdayStart))
                .order(by: "timestamp")
                .addSnapshotListener { [weak self] snap, _ in
                    guard let self, let snap else { return }
                    var events: [String: [(type: ClockEventType, ts: Date)]] = [:]
                    for doc in snap.documents {
                        let d = doc.data()
                        guard
                            let uid     = d["userId"]    as? String,
                            let ts      = (d["timestamp"] as? Timestamp)?.dateValue(),
                            let typeStr = d["type"]       as? String,
                            let type    = ClockEventType(rawValue: typeStr)
                        else { continue }
                        events[uid, default: []].append((type, ts))
                    }
                    chunkEvents[i] = events
                    // Merge all chunks and recompute
                    var merged: [String: [(type: ClockEventType, ts: Date)]] = [:]
                    for slot in chunkEvents {
                        for (uid, evs) in slot { merged[uid, default: []].append(contentsOf: evs) }
                    }
                    var open = Set<String>(); var dates: [String: Date] = [:]
                    for (uid, evs) in merged {
                        var lastIn: Date? = nil
                        for ev in evs.sorted(by: { $0.ts < $1.ts }) {
                            if ev.type == .clockIn  { lastIn = ev.ts }
                            if ev.type == .clockOut { lastIn = nil   }
                        }
                        if let lastIn, lastIn < todayStart { open.insert(uid); dates[uid] = lastIn }
                    }
                    self.openSessionUserIds = open
                    self.openSessionDates   = dates
                    self.recomputeManagerBadge()
                }
            listeners.append(l)
        }
    }

    /// Real-time listener: direct reports with an overtime note waiting for manager approval.
    private func listenPendingOvertime(reportIds: [String], workspaceId: String) {
        guard !reportIds.isEmpty else {
            pendingOvertimeUserIds = []; recomputeManagerBadge(); return
        }
        let chunks = stride(from: 0, to: reportIds.count, by: 30)
            .map { Array(reportIds[$0 ..< min($0 + 30, reportIds.count)]) }

        var chunkPending: [Set<String>] = Array(repeating: [], count: chunks.count)

        for (i, chunk) in chunks.enumerated() {
            let l = db.collection("clockEvents")
                .whereField("userId", in: chunk)
                .whereField("overtimeNote", isNotEqualTo: "")
                .addSnapshotListener { [weak self] snap, _ in
                    guard let self, let snap else { return }
                    var pending = Set<String>()
                    for doc in snap.documents {
                        let d = doc.data()
                        guard let uid = d["userId"] as? String, d["isOvertimeApproved"] == nil
                        else { continue }
                        pending.insert(uid)
                    }
                    chunkPending[i] = pending
                    self.pendingOvertimeUserIds = chunkPending.reduce(into: Set<String>()) { $0.formUnion($1) }
                    self.recomputeManagerBadge()
                }
            listeners.append(l)
        }
    }

    private func recomputeManagerBadge() {
        managerTeamBadgeCount  = openSessionUserIds.count + pendingOvertimeUserIds.count
        managerInboxBadgeCount = pendingRequestUserIds.count
    }

    // MARK: - Employee listener

    private var seenResolvedIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "mc_seenResolvedIds") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "mc_seenResolvedIds") }
    }

    private func listenForResolvedRequests(userId: String) {
        let l = db.collection("requests")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", in: ["approved", "rejected"])
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let snap else { return }
                let resolvedIds = Set(snap.documents.map { $0.documentID })
                employeeBadgeCount = resolvedIds.subtracting(self.seenResolvedIds).count
            }
        listeners.append(l)
    }
}
