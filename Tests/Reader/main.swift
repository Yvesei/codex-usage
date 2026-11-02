import Foundation

struct ReaderCase {
    let mode: String
    let expectedError: UsageReadError?
    let expectedAccount: String?
}

let cases = [
    ReaderCase(mode: "success", expectedError: nil, expectedAccount: "test@example.com"),
    ReaderCase(mode: "no_account", expectedError: .signInRequired, expectedAccount: nil),
    ReaderCase(mode: "api_key", expectedError: .chatGPTSignInRequired, expectedAccount: nil),
    ReaderCase(mode: "network_error", expectedError: .networkUnavailable, expectedAccount: "test@example.com"),
    ReaderCase(mode: "timeout_error", expectedError: .timedOut, expectedAccount: "test@example.com")
]

guard CommandLine.arguments.count == 2 else {
    fatalError("Provide the path to fake-codex.sh.")
}
let fakeExecutable = URL(fileURLWithPath: CommandLine.arguments[1])
var currentReader: CodexUsageReader?

func runCase(_ index: Int) {
    if index == cases.count {
        print("Codex reader handshake and error checks passed.")
        exit(0)
    }

    let test = cases[index]
    setenv("CODEX_USAGE_TEST_MODE", test.mode, 1)
    let reader = CodexUsageReader(executable: fakeExecutable)
    currentReader = reader
    var receivedAccount = false
    var actualAccount: String?
    reader.onAccountRead = { account in
        receivedAccount = true
        actualAccount = account
    }
    reader.read { result in
        guard receivedAccount, actualAccount == test.expectedAccount else {
            fatalError("Unexpected account callback for \(test.mode).")
        }
        switch result {
        case .success(let snapshot):
            guard test.expectedError == nil,
                  snapshot.fiveHour?.remainingPercent == 75,
                  snapshot.weekly?.remainingPercent == 60,
                  snapshot.accountEmail == "test@example.com" else {
                fatalError("Unexpected usage for \(test.mode).")
            }
        case .failure(let error):
            guard let expected = test.expectedError,
                  let actual = error as? UsageReadError,
                  actual == expected else {
                fatalError("Unexpected error for \(test.mode): \(error)")
            }
        }
        currentReader = nil
        runCase(index + 1)
    }
}

runCase(0)
RunLoop.main.run()
