import Foundation

final class ModelAnalyticsReader: NSObject, URLSessionTaskDelegate {
    private let environment: [String: String]
    private let now: () -> Date

    init(environment: [String: String] = ProcessInfo.processInfo.environment, now: @escaping () -> Date = Date.init) {
        self.environment = environment
        self.now = now
    }

    func currentIdentity() -> ModelAnalyticsIdentity? {
        return try? CodexAnalyticsCredentials.load(environment: environment).identity
    }

    func read(completion: @escaping (Result<ModelAnalyticsSnapshot, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            self.startRequest(completion: completion)
        }
    }

    private func startRequest(completion: @escaping (Result<ModelAnalyticsSnapshot, Error>) -> Void) {
        let credentials: CodexAnalyticsCredentials
        do {
            credentials = try CodexAnalyticsCredentials.load(environment: environment)
        } catch {
            completion(.failure(error))
            return
        }

        let requestTime = now()
        let range = AnalyticsDateRange(endingAt: requestTime)
        guard let first = range.dates.first, let last = range.dates.last,
              var components = URLComponents(string: "https://chatgpt.com/backend-api/wham/usage/daily-token-usage-breakdown") else {
            completion(.failure(ModelAnalyticsError.requestFailed))
            return
        }
        components.queryItems = [
            URLQueryItem(name: "start_date", value: first),
            URLQueryItem(name: "end_date", value: last),
            URLQueryItem(name: "group_by", value: "day")
        ]
        guard let url = components.url else {
            completion(.failure(ModelAnalyticsError.requestFailed))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.identity.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        session.dataTask(with: request) { data, response, error in
            defer {
                session.finishTasksAndInvalidate()
            }
            guard error == nil,
                  let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let data = data,
                  data.count <= 2 * 1024 * 1024 else {
                completion(.failure(ModelAnalyticsError.requestFailed))
                return
            }
            guard let current = try? CodexAnalyticsCredentials.load(environment: self.environment),
                  current.identity.accountID == credentials.identity.accountID,
                  current.identity.userID == credentials.identity.userID else {
                completion(.failure(ModelAnalyticsError.accountChanged))
                return
            }
            do {
                let snapshot = try ModelAnalyticsParser().parse(
                    data,
                    accountID: credentials.identity.accountID,
                    userID: credentials.identity.userID,
                    dates: range.dates,
                    fetchedAt: self.now()
                )
                completion(.success(snapshot))
            } catch {
                completion(.failure(ModelAnalyticsError.invalidResponse))
            }
        }.resume()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
