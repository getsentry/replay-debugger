import XCTest

@testable import SentryReplayDebugger

final class SentryURLParserTests: XCTestCase {

    // MARK: - Organizations Format (with project query param)

    func testParse_OrganizationsFormat_WithProject() throws {
        let result = try SentryURLParser.parse(url: "https://sentry.io/organizations/my-org/replays/abc123?project=456")
        XCTAssertEqual(result.orgSlug, "my-org")
        XCTAssertEqual(result.projectId, "456")
        XCTAssertEqual(result.replayId, "abc123")
    }

    func testParse_OrganizationsFormat_WithTrailingSlash() throws {
        let result = try SentryURLParser.parse(
            url: "https://sentry.io/organizations/test-org/replays/xyz789/?project=99")
        XCTAssertEqual(result.orgSlug, "test-org")
        XCTAssertEqual(result.projectId, "99")
        XCTAssertEqual(result.replayId, "xyz789")
    }

    func testParse_OrganizationsFormat_WithMultipleQueryParams() throws {
        let result = try SentryURLParser.parse(
            url: "https://sentry.io/organizations/company/replays/replay-123?project=456&environment=production")
        XCTAssertEqual(result.orgSlug, "company")
        XCTAssertEqual(result.projectId, "456")
        XCTAssertEqual(result.replayId, "replay-123")
    }

    func testParse_OrganizationsFormat_UUIDReplayId() throws {
        let result = try SentryURLParser.parse(
            url: "https://sentry.io/organizations/org/replays/550e8400-e29b-41d4-a716-446655440000?project=1")
        XCTAssertEqual(result.orgSlug, "org")
        XCTAssertEqual(result.replayId, "550e8400-e29b-41d4-a716-446655440000")
    }

    func testParse_OrganizationsFormat_MissingProject_Throws() {
        XCTAssertThrowsError(try SentryURLParser.parse(url: "https://sentry.io/organizations/my-org/replays/abc123")) {
            error in
            XCTAssertEqual(error as? SentryURLParseError, .missingProjectId)
        }
    }

    // MARK: - Web UI Format

    func testParse_WebUI_ValidURL() throws {
        let result = try SentryURLParser.parse(
            url: "https://sentry.sentry.io/explore/replays/1063229db9cd453d8fcdee3b2021cbf0/?project=11276")
        XCTAssertEqual(result.orgSlug, "sentry")
        XCTAssertEqual(result.projectId, "11276")
        XCTAssertEqual(result.replayId, "1063229db9cd453d8fcdee3b2021cbf0")
    }

    func testParse_WebUI_FullURL() throws {
        let result = try SentryURLParser.parse(
            url:
                "https://sentry.sentry.io/explore/replays/1063229db9cd453d8fcdee3b2021cbf0/?playlistEnd=2026-03-11T21%3A01%3A17&playlistStart=2026-03-04T21%3A01%3A17&project=11276&query=&referrer=replayList"
        )
        XCTAssertEqual(result.orgSlug, "sentry")
        XCTAssertEqual(result.projectId, "11276")
        XCTAssertEqual(result.replayId, "1063229db9cd453d8fcdee3b2021cbf0")
    }

    func testParse_WebUI_CustomOrg() throws {
        let result = try SentryURLParser.parse(url: "https://my-company.sentry.io/explore/replays/abc123/?project=42")
        XCTAssertEqual(result.orgSlug, "my-company")
        XCTAssertEqual(result.projectId, "42")
        XCTAssertEqual(result.replayId, "abc123")
    }

    func testParse_WebUI_NoTrailingSlash() throws {
        let result = try SentryURLParser.parse(url: "https://acme.sentry.io/explore/replays/abc123?project=7")
        XCTAssertEqual(result.orgSlug, "acme")
        XCTAssertEqual(result.projectId, "7")
        XCTAssertEqual(result.replayId, "abc123")
    }

    func testParse_WebUI_MissingProject_Throws() {
        XCTAssertThrowsError(try SentryURLParser.parse(url: "https://sentry.sentry.io/explore/replays/abc123/")) {
            error in
            XCTAssertEqual(error as? SentryURLParseError, .missingProjectId)
        }
    }

    func testParse_WebUI_NonSentryHost_Throws() {
        XCTAssertThrowsError(try SentryURLParser.parse(url: "https://example.com/explore/replays/abc123?project=1")) {
            error in
            XCTAssertEqual(error as? SentryURLParseError, .unrecognizedFormat)
        }
    }

    // MARK: - Invalid URLs

    func testParse_InvalidURL_Malformed() {
        XCTAssertThrowsError(try SentryURLParser.parse(url: "not a valid url")) { error in
            XCTAssertEqual(error as? SentryURLParseError, .invalidURL)
        }
    }

    func testParse_InvalidURL_EmptyString() {
        XCTAssertThrowsError(try SentryURLParser.parse(url: "")) { error in
            XCTAssertEqual(error as? SentryURLParseError, .invalidURL)
        }
    }

    func testParse_InvalidURL_OnlyDomain() {
        XCTAssertThrowsError(try SentryURLParser.parse(url: "https://sentry.io")) { error in
            XCTAssertEqual(error as? SentryURLParseError, .unrecognizedFormat)
        }
    }

    func testParse_InvalidURL_MissingReplays() {
        XCTAssertThrowsError(try SentryURLParser.parse(url: "https://sentry.io/organizations/my-org/123?project=1")) {
            error in
            XCTAssertEqual(error as? SentryURLParseError, .unrecognizedFormat)
        }
    }

    func testParse_InvalidURL_WrongKeyword() {
        XCTAssertThrowsError(
            try SentryURLParser.parse(url: "https://sentry.io/organisation/my-org/replays/123?project=1")
        ) { error in
            XCTAssertEqual(error as? SentryURLParseError, .unrecognizedFormat)
        }
    }

    // MARK: - Edge Cases

    func testParse_OrganizationsFormat_WithPort() throws {
        let result = try SentryURLParser.parse(url: "https://sentry.io:8080/organizations/my-org/replays/123?project=5")
        XCTAssertEqual(result.orgSlug, "my-org")
        XCTAssertEqual(result.projectId, "5")
        XCTAssertEqual(result.replayId, "123")
    }

    func testParse_OrganizationsFormat_Localhost() throws {
        let result = try SentryURLParser.parse(
            url: "http://localhost:3000/organizations/test-org/replays/test-123?project=10")
        XCTAssertEqual(result.orgSlug, "test-org")
        XCTAssertEqual(result.projectId, "10")
        XCTAssertEqual(result.replayId, "test-123")
    }

    // MARK: - canParse

    func testCanParse_ValidURL_ReturnsTrue() {
        XCTAssertTrue(SentryURLParser.canParse(url: "https://sentry.sentry.io/explore/replays/abc123/?project=1"))
    }

    func testCanParse_InvalidURL_ReturnsFalse() {
        XCTAssertFalse(SentryURLParser.canParse(url: "not a url"))
    }

    func testCanParse_MissingProject_ReturnsFalse() {
        XCTAssertFalse(SentryURLParser.canParse(url: "https://sentry.sentry.io/explore/replays/abc123/"))
    }
}
