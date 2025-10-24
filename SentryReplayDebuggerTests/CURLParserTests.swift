import XCTest
@testable import SentryReplayDebugger

final class CURLParserTests: XCTestCase {

    // MARK: - Basic URL Extraction Tests

    func testParse_SimpleURL_Unquoted() throws {
        // Given
        let curl = "curl https://api.sentry.io/test"

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.url.absoluteString, "https://api.sentry.io/test")
        XCTAssertTrue(result.headers.isEmpty)
        XCTAssertTrue(result.cookies.isEmpty)
    }

    func testParse_SimpleURL_SingleQuoted() throws {
        // Given
        let curl = "curl 'https://api.sentry.io/test'"

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.url.absoluteString, "https://api.sentry.io/test")
    }

    func testParse_SimpleURL_DoubleQuoted() throws {
        // Given
        let curl = "curl \"https://api.sentry.io/test\""

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.url.absoluteString, "https://api.sentry.io/test")
    }

    func testParse_URLWithQueryString() throws {
        // Given
        let curl = "curl 'https://api.sentry.io/api/0/test?param=value&foo=bar'"

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.url.absoluteString, "https://api.sentry.io/api/0/test?param=value&foo=bar")
    }

    func testParse_URLWithPort() throws {
        // Given
        let curl = "curl https://localhost:8080/api/test"

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.url.absoluteString, "https://localhost:8080/api/test")
    }

    // MARK: - Header Extraction Tests

    func testParse_SingleHeader_SingleQuoted() throws {
        // Given
        let curl = "curl 'https://api.sentry.io/test' -H 'accept: application/json'"

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.headers.count, 1)
        XCTAssertEqual(result.headers["accept"], "application/json")
    }

    func testParse_SingleHeader_DoubleQuoted() throws {
        // Given
        let curl = "curl \"https://api.sentry.io/test\" -H \"content-type: application/json\""

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.headers.count, 1)
        XCTAssertEqual(result.headers["content-type"], "application/json")
    }

    func testParse_MultipleHeaders() throws {
        // Given
        let curl = """
        curl 'https://api.sentry.io/test' \
        -H 'accept: application/json' \
        -H 'content-type: application/json' \
        -H 'user-agent: Mozilla/5.0'
        """

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.headers.count, 3)
        XCTAssertEqual(result.headers["accept"], "application/json")
        XCTAssertEqual(result.headers["content-type"], "application/json")
        XCTAssertEqual(result.headers["user-agent"], "Mozilla/5.0")
    }

    func testParse_FilteredHeaders_OnlyAllowed() throws {
        // Given
        let curl = """
        curl 'https://api.sentry.io/test' \
        -H 'accept: application/json' \
        -H 'authorization: Bearer token123' \
        -H 'user-agent: Mozilla/5.0' \
        -H 'x-custom-header: custom-value'
        """

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.headers.count, 2, "Should only include allowed headers")
        XCTAssertEqual(result.headers["accept"], "application/json")
        XCTAssertEqual(result.headers["user-agent"], "Mozilla/5.0")
        XCTAssertNil(result.headers["authorization"], "Authorization should be filtered out")
        XCTAssertNil(result.headers["x-custom-header"], "Custom header should be filtered out")
    }

    func testParse_AllAllowedHeaders() throws {
        // Given
        let curl = """
        curl 'https://api.sentry.io/test' \
        -H 'accept: */*' \
        -H 'accept-language: en-US' \
        -H 'cache-control: no-cache' \
        -H 'content-type: application/json' \
        -H 'origin: https://sentry.io' \
        -H 'pragma: no-cache' \
        -H 'referer: https://sentry.io/page' \
        -H 'user-agent: Mozilla/5.0'
        """

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.headers.count, 8)
        XCTAssertEqual(result.headers["accept"], "*/*")
        XCTAssertEqual(result.headers["accept-language"], "en-US")
        XCTAssertEqual(result.headers["cache-control"], "no-cache")
        XCTAssertEqual(result.headers["content-type"], "application/json")
        XCTAssertEqual(result.headers["origin"], "https://sentry.io")
        XCTAssertEqual(result.headers["pragma"], "no-cache")
        XCTAssertEqual(result.headers["referer"], "https://sentry.io/page")
        XCTAssertEqual(result.headers["user-agent"], "Mozilla/5.0")
    }

    func testParse_HeaderWithWhitespace() throws {
        // Given
        let curl = "curl 'https://api.sentry.io/test' -H 'accept:    application/json   '"

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.headers["accept"], "application/json")
    }

    func testParse_HeaderCaseInsensitive() throws {
        // Given
        let curl = """
        curl 'https://api.sentry.io/test' \
        -H 'Accept: application/json' \
        -H 'Content-Type: text/html' \
        -H 'USER-AGENT: Mozilla/5.0'
        """

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.headers["accept"], "application/json")
        XCTAssertEqual(result.headers["content-type"], "text/html")
        XCTAssertEqual(result.headers["user-agent"], "Mozilla/5.0")
    }

    // MARK: - Cookie Extraction Tests

    func testParse_SingleCookie_ShortOption() throws {
        // Given
        let curl = "curl 'https://api.sentry.io/test' -b 'session=abc123'"

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.cookies.count, 1)
        XCTAssertEqual(result.cookies["session"], "abc123")
    }

    func testParse_SingleCookie_LongOption() throws {
        // Given
        let curl = "curl 'https://api.sentry.io/test' --cookie 'session=xyz789'"

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.cookies.count, 1)
        XCTAssertEqual(result.cookies["session"], "xyz789")
    }

    func testParse_MultipleCookies_Semicolon() throws {
        // Given
        let curl = "curl 'https://api.sentry.io/test' -b 'session=abc123; sentry-auth=token456'"

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.cookies.count, 2)
        XCTAssertEqual(result.cookies["session"], "abc123")
        XCTAssertEqual(result.cookies["sentry-auth"], "token456")
    }

    func testParse_FilteredCookies_OnlySentryAndSession() throws {
        // Given
        let curl = """
        curl 'https://api.sentry.io/test' -b 'session=abc; sentry-auth=token; other=value; sentry-user=user123'
        """

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.cookies.count, 3, "Should only include session and sentry- prefixed cookies")
        XCTAssertEqual(result.cookies["session"], "abc")
        XCTAssertEqual(result.cookies["sentry-auth"], "token")
        XCTAssertEqual(result.cookies["sentry-user"], "user123")
        XCTAssertNil(result.cookies["other"], "Non-Sentry cookies should be filtered")
    }

    func testParse_CookieWithSpaces() throws {
        // Given
        let curl = "curl 'https://api.sentry.io/test' -b 'session=abc123 ; sentry-auth=token456'"

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.cookies["session"], "abc123")
        XCTAssertEqual(result.cookies["sentry-auth"], "token456")
    }

    func testParse_CookieCaseInsensitive() throws {
        // Given
        let curl = "curl 'https://api.sentry.io/test' -b 'SESSION=abc; Sentry-Auth=token; SENTRY-USER=user'"

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.cookies.count, 3)
        XCTAssertNotNil(result.cookies["SESSION"])
        XCTAssertNotNil(result.cookies["Sentry-Auth"])
        XCTAssertNotNil(result.cookies["SENTRY-USER"])
    }

    // MARK: - Multi-line CURL Tests

    func testParse_MultilineCURL_WithBackslashes() throws {
        // Given
        let curl = """
        curl 'https://api.sentry.io/api/0/test' \
        -H 'accept: application/json' \
        -H 'user-agent: Mozilla/5.0' \
        -b 'session=abc123; sentry-auth=token456'
        """

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.url.absoluteString, "https://api.sentry.io/api/0/test")
        XCTAssertEqual(result.headers.count, 2)
        XCTAssertEqual(result.cookies.count, 2)
    }

    func testParse_MultilineCURL_WithNewlines() throws {
        // Given
        let curl = """
        curl 'https://api.sentry.io/api/0/test'
        -H 'accept: application/json'
        -H 'content-type: application/json'
        -b 'session=xyz'
        """

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.url.absoluteString, "https://api.sentry.io/api/0/test")
        XCTAssertEqual(result.headers.count, 2)
        XCTAssertEqual(result.cookies.count, 1)
    }

    // MARK: - Complex Real-world Tests

    func testParse_CompleteRealWorldCURL() throws {
        // Given
        let curl = """
        curl 'https://sentry.io/api/0/organizations/test-org/replays/abc123/segments/' \
        -H 'accept: */*' \
        -H 'accept-language: en-US,en;q=0.9' \
        -H 'authorization: Bearer secret-token' \
        -H 'cache-control: no-cache' \
        -H 'content-type: application/json' \
        -H 'origin: https://sentry.io' \
        -H 'referer: https://sentry.io/organizations/test-org/replays/abc123/' \
        -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)' \
        -b 'session=abc123; sentry-auth=token456; _ga=GA1.2.123456; other-cookie=value'
        """

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.url.absoluteString, "https://sentry.io/api/0/organizations/test-org/replays/abc123/segments/")

        // Should have filtered headers (no authorization)
        XCTAssertEqual(result.headers.count, 7)
        XCTAssertEqual(result.headers["accept"], "*/*")
        XCTAssertEqual(result.headers["accept-language"], "en-US,en;q=0.9")
        XCTAssertNil(result.headers["authorization"])

        // Should have filtered cookies (only session and sentry- prefixed)
        XCTAssertEqual(result.cookies.count, 2)
        XCTAssertEqual(result.cookies["session"], "abc123")
        XCTAssertEqual(result.cookies["sentry-auth"], "token456")
        XCTAssertNil(result.cookies["_ga"])
        XCTAssertNil(result.cookies["other-cookie"])
    }

    // MARK: - Error Handling Tests

    func testParse_ThrowsError_InvalidURL() {
        // Given - Curl command where URL extraction fails
        let curl = "curl --help"

        // Then
        XCTAssertThrowsError(try CURLParser.parse(curlCommand: curl)) { error in
            XCTAssertTrue(error is CURLParserError)
            XCTAssertEqual(error as? CURLParserError, .invalidURL)
        }
    }

    func testParse_ThrowsError_MissingURL() {
        // Given
        let curl = "curl"

        // Then
        XCTAssertThrowsError(try CURLParser.parse(curlCommand: curl)) { error in
            XCTAssertTrue(error is CURLParserError)
        }
    }

    func testParse_ThrowsError_EmptyString() {
        // Given
        let curl = ""

        // Then
        XCTAssertThrowsError(try CURLParser.parse(curlCommand: curl))
    }

    func testParse_ThrowsError_OnlyHeaders() {
        // Given
        let curl = "-H 'accept: application/json'"

        // Then
        XCTAssertThrowsError(try CURLParser.parse(curlCommand: curl))
    }

    // MARK: - Edge Cases

    func testParse_EmptyHeaders() throws {
        // Given - CURL with no headers
        let curl = "curl 'https://api.sentry.io/test'"

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertTrue(result.headers.isEmpty)
    }

    func testParse_EmptyCookies() throws {
        // Given - CURL with no cookies
        let curl = "curl 'https://api.sentry.io/test' -H 'accept: */*'"

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertTrue(result.cookies.isEmpty)
    }

    func testParse_HeadersAndCookies_AllFiltered() throws {
        // Given - All headers and cookies should be filtered out
        let curl = """
        curl 'https://api.sentry.io/test' \
        -H 'x-custom: value' \
        -H 'authorization: Bearer token' \
        -b 'ga=123; other=value'
        """

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertTrue(result.headers.isEmpty, "All headers should be filtered")
        XCTAssertTrue(result.cookies.isEmpty, "All cookies should be filtered")
    }

    func testParse_DoubleQuotedMixed() throws {
        // Given - Mix of single and double quotes
        let curl = """
        curl "https://api.sentry.io/test" \
        -H "accept: application/json" \
        -b "session=abc123"
        """

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.url.absoluteString, "https://api.sentry.io/test")
        XCTAssertEqual(result.headers["accept"], "application/json")
        XCTAssertEqual(result.cookies["session"], "abc123")
    }

    func testParse_URLWithFragmentAndQuery() throws {
        // Given
        let curl = "curl 'https://api.sentry.io/test?query=1#fragment'"

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.url.absoluteString, "https://api.sentry.io/test?query=1#fragment")
    }

    func testParse_CookieValueWithEquals() throws {
        // Given - Cookie value contains '=' character
        let curl = "curl 'https://api.sentry.io/test' -b 'session=abc=def=ghi'"

        // When
        let result = try CURLParser.parse(curlCommand: curl)

        // Then
        XCTAssertEqual(result.cookies["session"], "abc=def=ghi")
    }
}

final class CURLParserErrorTests: XCTestCase {

    func testCURLParserError_InvalidURL_Description() {
        // Given
        let error = CURLParserError.invalidURL

        // Then
        XCTAssertEqual(error.errorDescription, "Could not extract valid URL from CURL command")
    }

    func testCURLParserError_InvalidFormat_Description() {
        // Given
        let error = CURLParserError.invalidFormat

        // Then
        XCTAssertEqual(error.errorDescription, "Invalid CURL command format")
    }
}
