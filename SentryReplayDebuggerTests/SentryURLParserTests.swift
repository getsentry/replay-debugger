import XCTest
@testable import SentryReplayDebugger

final class SentryURLParserTests: XCTestCase {

    // MARK: - Valid URL Tests

    func testParse_ValidSentryURL() {
        // Given
        let url = "https://sentry.io/organizations/my-org/replays/abc123"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.orgSlug, "my-org")
        XCTAssertEqual(result?.replayId, "abc123")
    }

    func testParse_ValidSentryURL_WithTrailingSlash() {
        // Given
        let url = "https://sentry.io/organizations/test-org/replays/xyz789/"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.orgSlug, "test-org")
        XCTAssertEqual(result?.replayId, "xyz789")
    }

    func testParse_ValidSentryURL_WithQueryString() {
        // Given
        let url = "https://sentry.io/organizations/company/replays/replay-123?project=456&environment=production"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.orgSlug, "company")
        XCTAssertEqual(result?.replayId, "replay-123")
    }

    func testParse_ValidSentryURL_WithFragment() {
        // Given
        let url = "https://sentry.io/organizations/org/replays/abc#details"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.orgSlug, "org")
        XCTAssertEqual(result?.replayId, "abc")
    }

    func testParse_ValidSentryURL_WithDifferentHost() {
        // Given
        let url = "https://custom.sentry.io/organizations/my-company/replays/uuid-1234"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.orgSlug, "my-company")
        XCTAssertEqual(result?.replayId, "uuid-1234")
    }

    func testParse_ValidSentryURL_WithHTTP() {
        // Given
        let url = "http://sentry.io/organizations/test/replays/123"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.orgSlug, "test")
        XCTAssertEqual(result?.replayId, "123")
    }

    func testParse_ValidSentryURL_WithNumericOrgSlug() {
        // Given
        let url = "https://sentry.io/organizations/12345/replays/abc"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.orgSlug, "12345")
        XCTAssertEqual(result?.replayId, "abc")
    }

    func testParse_ValidSentryURL_WithUUIDReplayId() {
        // Given
        let url = "https://sentry.io/organizations/org/replays/550e8400-e29b-41d4-a716-446655440000"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.orgSlug, "org")
        XCTAssertEqual(result?.replayId, "550e8400-e29b-41d4-a716-446655440000")
    }

    func testParse_ValidSentryURL_WithHyphenatedOrgSlug() {
        // Given
        let url = "https://sentry.io/organizations/my-complex-org-name/replays/replay-id"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.orgSlug, "my-complex-org-name")
        XCTAssertEqual(result?.replayId, "replay-id")
    }

    func testParse_ValidSentryURL_WithAdditionalPathComponents() {
        // Given
        let url = "https://sentry.io/organizations/org/replays/123/extra/path"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.orgSlug, "org")
        XCTAssertEqual(result?.replayId, "123")
    }

    // MARK: - Invalid URL Tests

    func testParse_InvalidURL_Malformed() {
        // Given
        let url = "not a valid url"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNil(result)
    }

    func testParse_InvalidURL_MissingOrganizations() {
        // Given
        let url = "https://sentry.io/my-org/replays/123"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNil(result)
    }

    func testParse_InvalidURL_MissingReplays() {
        // Given
        let url = "https://sentry.io/organizations/my-org/123"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNil(result)
    }

    func testParse_InvalidURL_MissingOrgSlug() {
        // Given
        let url = "https://sentry.io/organizations//replays/123"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNil(result)
    }

    func testParse_InvalidURL_MissingReplayId() {
        // Given
        let url = "https://sentry.io/organizations/my-org/replays/"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNil(result)
    }

    func testParse_InvalidURL_WrongOrder() {
        // Given
        let url = "https://sentry.io/replays/123/organizations/my-org"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNil(result)
    }

    func testParse_InvalidURL_TooShortPath() {
        // Given
        let url = "https://sentry.io/organizations/my-org"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNil(result)
    }

    func testParse_InvalidURL_EmptyString() {
        // Given
        let url = ""

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNil(result)
    }

    func testParse_InvalidURL_OnlyDomain() {
        // Given
        let url = "https://sentry.io"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNil(result)
    }

    func testParse_InvalidURL_WrongKeyword_Organizations() {
        // Given
        let url = "https://sentry.io/organisation/my-org/replays/123"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNil(result)
    }

    func testParse_InvalidURL_WrongKeyword_Replays() {
        // Given
        let url = "https://sentry.io/organizations/my-org/replay/123"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNil(result)
    }

    // MARK: - Edge Case Tests

    func testParse_WithPort() {
        // Given
        let url = "https://sentry.io:8080/organizations/my-org/replays/123"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.orgSlug, "my-org")
        XCTAssertEqual(result?.replayId, "123")
    }

    func testParse_WithUsernamePassword() {
        // Given
        let url = "https://user:pass@sentry.io/organizations/org/replays/123"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.orgSlug, "org")
        XCTAssertEqual(result?.replayId, "123")
    }

    func testParse_WithLocalhost() {
        // Given
        let url = "http://localhost:3000/organizations/test-org/replays/test-123"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.orgSlug, "test-org")
        XCTAssertEqual(result?.replayId, "test-123")
    }

    func testParse_WithIPAddress() {
        // Given
        let url = "http://127.0.0.1:8000/organizations/local-org/replays/local-123"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.orgSlug, "local-org")
        XCTAssertEqual(result?.replayId, "local-123")
    }

    func testParse_WithEncodedCharacters() {
        // Given
        let url = "https://sentry.io/organizations/my%20org/replays/123"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNotNil(result)
        // URL parser automatically decodes percent-encoded characters
        XCTAssertEqual(result?.orgSlug, "my org")
        XCTAssertEqual(result?.replayId, "123")
    }

    func testParse_WithSpecialCharacters() {
        // Given
        let url = "https://sentry.io/organizations/my_org-123/replays/replay_id-456"

        // When
        let result = SentryURLParser.parse(url: url)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.orgSlug, "my_org-123")
        XCTAssertEqual(result?.replayId, "replay_id-456")
    }
}
