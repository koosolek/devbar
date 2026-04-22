import Testing
import Foundation
@testable import DevBar

@Test func logURLMatcherPrefersListeningPortMatch() {
    let log = """
    [2024-01-01] Starting services...
    Connecting to redis at redis://localhost:6379
    Available at https://tenant1.cds-dev.com:8000/
    Visit docs: https://docs.example.com/guide
    """
    let url = LogURLDetector.matchURL(in: log, against: [8000, 5432])
    #expect(url?.absoluteString == "https://tenant1.cds-dev.com:8000/")
}

@Test func logURLMatcherReturnsLatestWhenMultipleMatch() {
    let log = """
    Listening on http://localhost:3000
    ...
    Server ready at http://localhost:3000/app
    """
    let url = LogURLDetector.matchURL(in: log, against: [3000])
    // Later in-log occurrence wins so steady-state output trumps startup messages
    #expect(url?.absoluteString == "http://localhost:3000/app")
}

@Test func logURLMatcherIgnoresUnlistenedPorts() {
    let log = "Only see this URL: http://localhost:9999"
    let url = LogURLDetector.matchURL(in: log, against: [3000, 8000])
    #expect(url == nil)
}

@Test func logURLMatcherSkipsDocsHosts() {
    let log = "See https://docs.example.com:443/help for instructions"
    let url = LogURLDetector.matchURL(in: log, against: [443])
    #expect(url == nil)
}

@Test func logURLMatcherStripsTrailingPunctuation() {
    let log = "Open at http://localhost:3000."
    let url = LogURLDetector.matchURL(in: log, against: [3000])
    #expect(url?.absoluteString == "http://localhost:3000")
}
