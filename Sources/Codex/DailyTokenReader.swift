import Foundation

enum DailyTokenReadError: LocalizedError, Equatable {
    case codexNotFound
    case signInRequired
    case chatGPTSignInRequired
    case invalidResponse
    case requestFailed
    case networkUnavailable
    case timedOut
    case unsupported

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "Codex was not found. Install the Codex CLI and try again."
        case .signInRequired:
            return "Sign in to Codex with your ChatGPT account, then try again."
        case .chatGPTSignInRequired:
            return "Sign in to Codex with ChatGPT to see token usage."
        case .invalidResponse:
            return "Codex returned an incomplete token usage response."
        case .requestFailed:
            return "Couldn't update token usage. Please try again."
        case .networkUnavailable:
            return "Couldn't connect to Codex. Check your internet connection and try again."
        case .timedOut:
            return "The token usage request timed out. Please try again."
        case .unsupported:
            return "This version of Codex doesn't report daily token usage."
        }
    }
}

final class DailyTokenReader {
    var onAccountRead: ((String?) -> Void)?

    private let locator = CodexExecutableLocator()
    private let parser = DailyTokenParser()
    private let executableOverride: URL?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var completion: ((Result<DailyTokenUsage, Error>) -> Void)?
    private var timeout: DispatchWorkItem?
    private var accountEmail: String?

    init(executable: URL? = nil) {
        executableOverride = executable
    }

    func read(completion: @escaping (Result<DailyTokenUsage, Error>) -> Void) {
        precondition(Thread.isMainThread)
        guard self.completion == nil else {
            completion(.failure(DailyTokenReadError.requestFailed))
            return
        }
        self.completion = completion

        guard let executable = executableOverride ?? locator.find() else {
            finish(.failure(DailyTokenReadError.codexNotFound))
            return
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        process.environment = locator.environment(for: executable)

        self.process = process
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                guard let self, let process, self.process === process else {
                    return
                }
                self.consume(data)
            }
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            DispatchQueue.main.async {
                guard let self, self.process === terminatedProcess else {
                    return
                }
                self.finish(.failure(DailyTokenReadError.requestFailed))
            }
        }

        do {
            try process.run()
            startTimeout()
            sendInitialize()
        } catch {
            finish(.failure(DailyTokenReadError.requestFailed))
        }
    }

    private func startTimeout() {
        let work = DispatchWorkItem { [weak self] in
            self?.finish(.failure(DailyTokenReadError.timedOut))
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    private func sendInitialize() {
        let clientInfo: [String: Any] = [
            "name": "codex-usage-menu",
            "title": "Codex Usage Menu",
            "version": "1.0.0"
        ]
        let capabilities: [String: Any] = [
            "experimentalApi": false,
            "requestAttestation": false
        ]
        let params: [String: Any] = ["clientInfo": clientInfo, "capabilities": capabilities]
        send(["id": 1, "method": "initialize", "params": params])
    }

    private func sendAccountRequest() {
        send(["method": "initialized"])
        send(["id": 2, "method": "account/read", "params": ["refreshToken": false]])
    }

    private func send(_ request: [String: Any]) {
        guard completion != nil, let input = input else {
            return
        }
        do {
            var data = try JSONSerialization.data(withJSONObject: request)
            data.append(0x0A)
            try input.write(contentsOf: data)
        } catch {
            finish(.failure(DailyTokenReadError.requestFailed))
        }
    }

    private func consume(_ data: Data) {
        guard completion != nil, !data.isEmpty else {
            return
        }
        buffer.append(data)

        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer.prefix(upTo: newline))
            buffer.removeSubrange(...newline)
            handleLine(line)
        }
    }

    private func handleLine(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line),
              let response = object as? [String: Any],
              let id = response["id"] as? Int else {
            return
        }

        if let error = response["error"] as? [String: Any] {
            finish(.failure(classify(error: error, requestID: id)))
            return
        }
        guard let result = response["result"] as? [String: Any] else {
            finish(.failure(DailyTokenReadError.invalidResponse))
            return
        }

        switch id {
        case 1:
            sendAccountRequest()
        case 2:
            handleAccount(result)
        case 3:
            handleUsage(line)
        default:
            break
        }
    }

    private func handleAccount(_ result: [String: Any]) {
        guard let account = result["account"] as? [String: Any] else {
            onAccountRead?(nil)
            finish(.failure(DailyTokenReadError.signInRequired))
            return
        }
        guard let type = account["type"] as? String else {
            finish(.failure(DailyTokenReadError.invalidResponse))
            return
        }
        guard type == "chatgpt" else {
            onAccountRead?(nil)
            finish(.failure(DailyTokenReadError.chatGPTSignInRequired))
            return
        }

        if let email = account["email"] as? String, !email.isEmpty {
            accountEmail = email
            onAccountRead?(email)
        }
        send(["id": 3, "method": "account/usage/read"])
    }

    private func handleUsage(_ line: Data) {
        do {
            let usage = try parser.parse(line, accountEmail: accountEmail)
            finish(.success(usage))
        } catch {
            finish(.failure(DailyTokenReadError.invalidResponse))
        }
    }

    private func classify(error: [String: Any], requestID: Int) -> DailyTokenReadError {
        if requestID == 3, let code = error["code"] as? Int, code == -32601 {
            return .unsupported
        }
        let message = (error["message"] as? String ?? "").lowercased()
        if message.contains("unauthorized") || message.contains("not authenticated") || message.contains("sign in") {
            return .signInRequired
        }
        if message.contains("timed out") || message.contains("timeout") {
            return .timedOut
        }
        if message.contains("network") || message.contains("connection") || message.contains("dns") || message.contains("error sending request") {
            return .networkUnavailable
        }
        return .requestFailed
    }

    private func finish(_ result: Result<DailyTokenUsage, Error>) {
        guard let callback = completion else {
            return
        }
        completion = nil
        timeout?.cancel()
        timeout = nil
        output?.readabilityHandler = nil

        if process?.isRunning == true {
            process?.terminate()
        }

        process = nil
        input = nil
        output = nil
        accountEmail = nil
        buffer.removeAll()
        callback(result)
    }
}
