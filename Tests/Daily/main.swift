import Foundation

struct TestCase {
    let mode: String
    let expectedError: DailyTokenReadError?
    let expectedAccount: String?
}

let cases = [
    TestCase(mode: "success", expectedError: nil, expectedAccount: "test@example.com"),
    TestCase(mode: "null", expectedError: nil, expectedAccount: "test@example.com"),
    TestCase(mode: "empty", expectedError: nil, expectedAccount: "test@example.com"),
    TestCase(mode: "invalid_date", expectedError: .invalidResponse, expectedAccount: "test@example.com"),
    TestCase(mode: "negative", expectedError: .invalidResponse, expectedAccount: "test@example.com"),
    TestCase(mode: "boolean", expectedError: .invalidResponse, expectedAccount: "test@example.com"),
    TestCase(mode: "unsupported", expectedError: .unsupported, expectedAccount: "test@example.com"),
    TestCase(mode: "network_error", expectedError: .networkUnavailable, expectedAccount: "test@example.com"),
    TestCase(mode: "no_account", expectedError: .signInRequired, expectedAccount: nil),
    TestCase(mode: "api_key", expectedError: .chatGPTSignInRequired, expectedAccount: nil)
]

guard CommandLine.arguments.count == 2 else {
    fatalError("Provide the path to fake-codex.sh.")
}
let executable = URL(fileURLWithPath: CommandLine.arguments[1])
var currentReader: DailyTokenReader?

func runCase(_ index: Int) {
    if index == cases.count {
        print("Daily token reader checks passed.")
        exit(0)
    }

    let test = cases[index]
    setenv("DAILY_TOKEN_TEST_MODE", test.mode, 1)
    let reader = DailyTokenReader(executable: executable)
    currentReader = reader
    var receivedAccount = false
    var account: String?
    reader.onAccountRead = { value in
        receivedAccount = true
        account = value
    }
    reader.read { result in
        guard receivedAccount, account == test.expectedAccount else {
            fatalError("Unexpected account callback for \(test.mode).")
        }
        switch result {
        case .success(let usage):
            guard test.expectedError == nil, usage.accountEmail == test.expectedAccount else {
                fatalError("Unexpected success for \(test.mode).")
            }
            if test.mode == "null", usage.buckets != nil {
                fatalError("Unavailable buckets must remain nil.")
            }
            if test.mode == "empty", usage.buckets != [] {
                fatalError("An empty result must remain empty.")
            }
            if test.mode == "success" {
                guard let buckets = usage.buckets,
                      buckets.count == 2,
                      buckets[0].startDate == "2024-02-29",
                      buckets[0].tokens == 9_007_199_254_740_993,
                      buckets[1].tokens == 0 else {
                    fatalError("Token buckets were not decoded exactly.")
                }
            }
        case .failure(let error):
            guard let expected = test.expectedError,
                  let actual = error as? DailyTokenReadError,
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
