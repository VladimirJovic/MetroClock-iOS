import Foundation

enum TaskProvider: String {
    case clickup
    case asana
    case jira
}

struct ExternalTask: Identifiable, Hashable {
    var id: String
    var name: String
    var listName: String?
    var folderName: String?
    var spaceName: String?
    var status: String
    var provider: TaskProvider

    var displayName: String {
        var parts: [String] = []
        if let space = spaceName, space != "hidden" { parts.append(space) }
        if let folder = folderName, folder != "hidden" { parts.append(folder) }
        if let list = listName { parts.append(list) }
        parts.append(name)
        return parts.joined(separator: " › ")
    }
}

@Observable
class TaskService {
    var tasks: [ExternalTask] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var isAvailable: Bool = false

    private var lastConfig: WorkspaceConfig?
    private var lastMetroUserId: String?

    func refresh() {
        guard let config = lastConfig, let userId = lastMetroUserId else { return }
        fetchTasks(config: config, metroUserId: userId)
    }

    func fetchTasks(config: WorkspaceConfig, metroUserId: String) {
        lastConfig = config
        lastMetroUserId = metroUserId
        tasks = []
        errorMessage = nil

        if let token = config.clickupApiToken,
           let clickupUserId = config.clickupUserMappings[metroUserId] {
            isAvailable = true
            fetchClickUpTasks(token: token, clickupUserId: clickupUserId)
            return
        }

        // Future providers:
        // if let token = config.asanaToken, let asanaId = config.asanaUserMappings[metroUserId] {
        //     isAvailable = true
        //     fetchAsanaTasks(token: token, asanaUserId: asanaId)
        //     return
        // }

        isAvailable = false
    }

    // MARK: - ClickUp

    private func fetchClickUpTasks(token: String, clickupUserId: String) {
        isLoading = true
        fetchClickUpTeams(token: token) { [weak self] teamIds in
            guard let self = self, let teamId = teamIds.first else {
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.errorMessage = "No workspace found"
                }
                return
            }
            self.fetchClickUpTasksForTeam(token: token, teamId: teamId, clickupUserId: clickupUserId)
        }
    }

    private func fetchClickUpTeams(token: String, completion: @escaping ([String]) -> Void) {
        guard let url = URL(string: "https://api.clickup.com/api/v2/team") else { completion([]); return }
        var req = URLRequest(url: url)
        req.setValue(token, forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let teams = json["teams"] as? [[String: Any]] else { completion([]); return }
            completion(teams.compactMap { $0["id"] as? String })
        }.resume()
    }

    private func fetchClickUpTasksForTeam(token: String, teamId: String, clickupUserId: String) {
        var comps = URLComponents(string: "https://api.clickup.com/api/v2/team/\(teamId)/task")!
        comps.queryItems = [
            URLQueryItem(name: "assignees[]", value: clickupUserId),
            URLQueryItem(name: "include_closed", value: "false"),
            URLQueryItem(name: "subtasks", value: "true"),
            URLQueryItem(name: "page", value: "0"),
            URLQueryItem(name: "include_archived_lists", value: "false")
        ]
        guard let url = comps.url else {
            DispatchQueue.main.async { self.isLoading = false }
            return
        }
        var req = URLRequest(url: url)
        req.setValue(token, forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                guard let data = data, error == nil,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let taskArray = json["tasks"] as? [[String: Any]] else {
                    self.errorMessage = error?.localizedDescription ?? "Failed to load tasks"
                    return
                }
                self.tasks = taskArray.compactMap { task in
                    guard let id = task["id"] as? String,
                          let name = task["name"] as? String else { return nil }
                    let status = (task["status"] as? [String: Any])?["status"] as? String ?? ""
                    let listName = (task["list"] as? [String: Any])?["name"] as? String
                    let folderName = (task["folder"] as? [String: Any])?["name"] as? String
                    let spaceName = (task["space"] as? [String: Any])?["name"] as? String
                    return ExternalTask(
                        id: id,
                        name: name,
                        listName: listName,
                        folderName: folderName,
                        spaceName: spaceName,
                        status: status,
                        provider: .clickup
                    )
                }
            }
        }.resume()
    }
}
