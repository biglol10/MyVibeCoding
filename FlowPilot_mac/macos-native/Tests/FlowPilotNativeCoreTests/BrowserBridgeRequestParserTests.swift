import XCTest
@testable import FlowPilotNativeCore

final class BrowserBridgeRequestParserTests: XCTestCase {
    func testAcceptsCompleteAuthenticatedJSONRequest() {
        let body = #"{"domain":"chatgpt.com","title":"ChatGPT"}"#
        let request = """
        POST /browser-event HTTP/1.1\r
        Content-Type: application/json; charset=utf-8\r
        X-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """

        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(Data(request.utf8), isComplete: false),
            .accepted(BrowserEventDraft(domain: "chatgpt.com", url: nil, title: "ChatGPT"))
        )
    }

    func testRejectsDuplicateHeadersWithoutTrapping() {
        let request = """
        POST /browser-event HTTP/1.1\r
        Content-Type: application/json\r
        Content-Type: application/json\r
        X-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r
        Content-Length: 2\r
        \r
        {}
        """

        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(Data(request.utf8), isComplete: true),
            .badRequest
        )
    }

    func testRejectsWhitespaceBetweenRequiredHeaderNamesAndColon() {
        let body = #"{"domain":"example.com","title":"Whitespace"}"#
        let malformedHeaderSets = [
            [
                "Content-Type : application/json",
                "X-FlowPilot-Bridge: flowpilot-browser-bridge-v1",
                "Content-Length: \(body.utf8.count)"
            ],
            [
                "Content-Type: application/json",
                "X-FlowPilot-Bridge\t: flowpilot-browser-bridge-v1",
                "Content-Length: \(body.utf8.count)"
            ],
            [
                "Content-Type: application/json",
                "X-FlowPilot-Bridge: flowpilot-browser-bridge-v1",
                "Content-Length : \(body.utf8.count)"
            ]
        ]

        for malformedHeaders in malformedHeaderSets {
            let request = Data(([
                "POST /browser-event HTTP/1.1"
            ] + malformedHeaders).joined(separator: "\r\n").utf8)
                + Data("\r\n\r\n\(body)".utf8)

            XCTAssertEqual(
                BrowserBridgeRequestParser.parse(request, isComplete: true),
                .badRequest,
                "Header bytes \(Array(malformedHeaders.joined(separator: "\r\n").utf8)) must be rejected"
            )
        }
    }

    func testRejectsCompletedMalformedHeaderLineBeforeHeaderTerminatorArrives() {
        let malformedPrefixes = [
            Data("POST /browser-event HTTP/1.1\r\nContent-Type : application/json\r\n".utf8),
            Data("POST /browser-event HTTP/1.1\r\nX-FlowPilot-Bridge\t: flowpilot-browser-bridge-v1\r\n".utf8),
            Data("POST /browser-event HTTP/1.1\r\nContent-Length : 2\r\n".utf8)
        ]

        for malformedPrefix in malformedPrefixes {
            XCTAssertEqual(
                BrowserBridgeRequestParser.parse(malformedPrefix, isComplete: false),
                .badRequest
            )
        }
    }

    func testReturnsIncompleteUntilDeclaredBodyArrives() {
        let request = """
        POST /browser-event HTTP/1.1\r
        Content-Type: application/json\r
        X-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r
        Content-Length: 10\r
        \r
        {}
        """

        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(Data(request.utf8), isComplete: false),
            .incomplete
        )
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(Data(request.utf8), isComplete: true),
            .badRequest
        )
    }

    func testRejectsHeaderAndBodySizeLimits() {
        let oversizedHeader = "POST /browser-event HTTP/1.1\r\nX-Fill: \(String(repeating: "a", count: 4097))"
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(Data(oversizedHeader.utf8), isComplete: false),
            .payloadTooLarge
        )

        let body = String(repeating: "a", count: 16 * 1024 + 1)
        let oversizedBody = "POST /browser-event HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(Data(oversizedBody.utf8), isComplete: true),
            .payloadTooLarge
        )
    }

    func testPersistenceFailureMapsTo500InsteadOf204() {
        let draft = BrowserEventDraft(domain: "example.com", url: nil, title: "Example")

        XCTAssertEqual(
            BrowserBridgeResponsePolicy.status(
                parseResult: .accepted(draft),
                persistenceSucceeded: false
            ),
            .internalServerError
        )
        XCTAssertEqual(
            BrowserBridgeResponsePolicy.status(
                parseResult: .accepted(draft),
                persistenceSucceeded: true
            ),
            .noContent
        )
    }

    func testMapsInvalidProtocolRequestsToSpecificClientErrors() {
        let cases: [(String, BrowserBridgeParseResult)] = [
            (
                "GET /browser-event HTTP/1.1\r\nContent-Length: 0\r\n\r\n",
                .methodNotAllowed
            ),
            (
                "POST /wrong HTTP/1.1\r\nContent-Length: 0\r\n\r\n",
                .notFound
            ),
            (
                "POST /browser-event HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}",
                .forbidden
            ),
            (
                "POST /browser-event HTTP/1.1\r\nContent-Type: text/plain\r\nX-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r\nContent-Length: 2\r\n\r\n{}",
                .forbidden
            ),
            (
                "POST /browser-event HTTP/1.1\r\nContent-Type: application/json\r\nX-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r\nContent-Length: 1\r\n\r\n{",
                .badRequest
            ),
            (
                "POST /browser-event HTTP/1.1\r\nContent-Type: application/json\r\nX-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r\nContent-Length: 2\r\n\r\n{}extra",
                .badRequest
            )
        ]

        for (request, expected) in cases {
            XCTAssertEqual(
                BrowserBridgeRequestParser.parse(Data(request.utf8), isComplete: true),
                expected
            )
        }
    }

    func testRejectsDuplicateHeadersCaseInsensitively() {
        let request = "POST /browser-event HTTP/1.1\r\nContent-Length: 2\r\ncontent-length: 2\r\n\r\n{}"

        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(Data(request.utf8), isComplete: true),
            .badRequest
        )
    }

    func testRequiresAValidNonNegativeContentLength() {
        for contentLength in ["-1", "two", ""] {
            let request = "POST /browser-event HTTP/1.1\r\nContent-Type: application/json\r\nX-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r\nContent-Length: \(contentLength)\r\n\r\n{}"
            XCTAssertEqual(
                BrowserBridgeRequestParser.parse(Data(request.utf8), isComplete: true),
                .badRequest,
                "Content-Length \(contentLength.debugDescription) must be rejected"
            )
        }
    }

    func testRejectsMissingContentLengthAndMalformedHeaderLines() {
        let missingContentLength = "POST /browser-event HTTP/1.1\r\nContent-Type: application/json\r\nX-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r\n\r\n{}"
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(Data(missingContentLength.utf8), isComplete: true),
            .badRequest
        )

        let malformedHeader = "POST /browser-event HTTP/1.1\r\nContent-Type application/json\r\n\r\n"
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(Data(malformedHeader.utf8), isComplete: true),
            .badRequest
        )
    }

    func testRejectsInvalidUTF8InHeadersAndBody() {
        let invalidHeader = Data([0x50, 0x4F, 0x53, 0x54, 0x20, 0x2F, 0x62, 0x72, 0x6F, 0x77, 0x73, 0x65, 0x72, 0x2D, 0x65, 0x76, 0x65, 0x6E, 0x74, 0x20, 0x48, 0x54, 0x54, 0x50, 0x2F, 0x31, 0x2E, 0x31, 0x0D, 0x0A, 0xFF, 0x3A, 0x20, 0x78, 0x0D, 0x0A, 0x0D, 0x0A])
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(invalidHeader, isComplete: true),
            .badRequest
        )

        var invalidBody = Data("POST /browser-event HTTP/1.1\r\nContent-Type: application/json\r\nX-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r\nContent-Length: 1\r\n\r\n".utf8)
        invalidBody.append(0xFF)
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(invalidBody, isComplete: true),
            .badRequest
        )
    }

    func testReturnsIncompleteOnlyForPotentiallyValidPartialRequests() {
        let partialHeaders = Data("POST /browser-event HTTP/1.1\r\nContent-Length: 2\r\n".utf8)
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(partialHeaders, isComplete: false),
            .incomplete
        )
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(partialHeaders, isComplete: true), .badRequest)

        let extraBodyBytes = Data("POST /browser-event HTTP/1.1\r\nContent-Type: application/json\r\nX-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r\nContent-Length: 2\r\n\r\n{}x".utf8)
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(extraBodyBytes, isComplete: false),
            .badRequest
        )
    }

    func testReturnsTerminalMethodAndRouteErrorsBeforeHeadersFinish() {
        let unsupportedMethod = Data("GET /browser-event HTTP/1.1\r\n".utf8)
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(unsupportedMethod, isComplete: false),
            .methodNotAllowed
        )

        let unsupportedRoute = Data("POST /wrong HTTP/1.1\r\n".utf8)
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(unsupportedRoute, isComplete: false),
            .notFound
        )
    }

    func testRejectsIrrecoverableDuplicateHeaderBeforeHeaderTerminatorArrives() {
        let request = Data("POST /browser-event HTTP/1.1\r\nContent-Length: 2\r\ncontent-length: 2\r\n".utf8)

        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(request, isComplete: false),
            .badRequest
        )
    }

    func testRejectsBareLineFeedsInPartialHeaders() {
        let request = Data("POST /browser-event HTTP/1.1\r\nContent-Length: 2\n\r\n".utf8)

        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(request, isComplete: false),
            .badRequest
        )
    }

    func testKeepsValidFragmentedCRLFSequencesIncomplete() {
        let prefix = "POST /browser-event HTTP/1.1\r\nContent-Length: 2"

        for fragment in ["\r", "\r\n\r"] {
            XCTAssertEqual(
                BrowserBridgeRequestParser.parse(Data((prefix + fragment).utf8), isComplete: false),
                .incomplete,
                "\(fragment.debugDescription) can still complete a CRLF sequence"
            )
        }
    }

    func testKeepsFragmentedRequestLineTerminatorIncomplete() {
        let requestLine = "POST /browser-event HTTP/1.1"

        for fragment in ["\r", "\r\n"] {
            XCTAssertEqual(
                BrowserBridgeRequestParser.parse(Data((requestLine + fragment).utf8), isComplete: false),
                .incomplete,
                "\(fragment.debugDescription) can still finish the request line"
            )
        }
    }

    func testRejectsBareCRAndLFInsideCompletedHeaders() {
        let body = #"{"domain":"example.com","title":"Bare line ending"}"#
        let cases = [
            "POST /browser-event HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\r\nContent-Type: application/json\r\nX-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r\n\r\n\(body)",
            "POST /browser-event HTTP/1.1\r\nContent-Length: \(body.utf8.count)\n\r\nContent-Type: application/json\r\nX-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r\n\r\n\(body)"
        ]

        for request in cases {
            XCTAssertEqual(
                BrowserBridgeRequestParser.parse(Data(request.utf8), isComplete: true),
                .badRequest
            )
        }
    }

    func testKeepsPartialUTF8HeaderCodePointIncompleteButRejectsPermanentInvalidUTF8() {
        var partialUTF8 = Data("POST /browser-event HTTP/1.1\r\nX-Note: ".utf8)
        partialUTF8.append(contentsOf: [0xE2, 0x82])
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(partialUTF8, isComplete: false),
            .incomplete
        )

        var invalidUTF8 = Data("POST /browser-event HTTP/1.1\r\nX-Note: ".utf8)
        invalidUTF8.append(0xFF)
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(invalidUTF8, isComplete: false),
            .badRequest
        )
    }

    func testHonorsExactHeaderLimitAndOnlyAllowsDelimiterPrefixesThatFit() {
        let body = #"{"domain":"example.com","title":"Header boundary"}"#
        let header = headerPaddedToExactly4KiB(contentLength: body.utf8.count)
        let completeRequest = header + Data(body.utf8)

        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(completeRequest, isComplete: false),
            .accepted(BrowserEventDraft(domain: "example.com", url: nil, title: "Header boundary"))
        )

        for partialHeaderLength in [4093, 4094, 4095] {
            XCTAssertEqual(
                BrowserBridgeRequestParser.parse(header.prefix(partialHeaderLength), isComplete: false),
                .incomplete,
                "A delimiter prefix at byte \(partialHeaderLength) still fits within 4 KiB"
            )
        }

        var exactLimitWithoutDelimiter = header
        exactLimitWithoutDelimiter[exactLimitWithoutDelimiter.index(exactLimitWithoutDelimiter.endIndex, offsetBy: -1)] = 0x58
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(exactLimitWithoutDelimiter, isComplete: false),
            .payloadTooLarge
        )

        var oneByteOverHeader = header
        oneByteOverHeader.insert(0x61, at: oneByteOverHeader.index(oneByteOverHeader.endIndex, offsetBy: -4))
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(oneByteOverHeader, isComplete: false),
            .payloadTooLarge
        )
    }

    func testHonorsExactBodyAndRequestLimits() {
        let title = String(repeating: "a", count: 16_349)
        let body = "{\"domain\":\"example.com\",\"title\":\"\(title)\"}"
        XCTAssertEqual(body.utf8.count, 16 * 1024)

        let ordinaryHeader = Data("POST /browser-event HTTP/1.1\r\nContent-Type: application/json\r\nX-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r\nContent-Length: \(body.utf8.count)\r\n\r\n".utf8)
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(ordinaryHeader + Data(body.utf8), isComplete: true),
            .accepted(BrowserEventDraft(domain: "example.com", url: nil, title: title))
        )

        let tooLargeBody = body + "a"
        let tooLargeBodyHeader = Data("POST /browser-event HTTP/1.1\r\nContent-Type: application/json\r\nX-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r\nContent-Length: \(tooLargeBody.utf8.count)\r\n\r\n".utf8)
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(tooLargeBodyHeader + Data(tooLargeBody.utf8), isComplete: true),
            .payloadTooLarge
        )

        let fourKiBHeader = headerPaddedToExactly4KiB(contentLength: body.utf8.count)
        let exactRequest = fourKiBHeader + Data(body.utf8)
        XCTAssertEqual(exactRequest.count, 20 * 1024)
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(exactRequest, isComplete: true),
            .accepted(BrowserEventDraft(domain: "example.com", url: nil, title: title))
        )
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(exactRequest + Data([0x00]), isComplete: true),
            .payloadTooLarge
        )
    }

    func testResponsePolicyLeavesIncompleteAndUnpersistedAcceptanceUnanswered() {
        let draft = BrowserEventDraft(domain: "example.com", url: nil, title: "Example")

        XCTAssertNil(BrowserBridgeResponsePolicy.status(parseResult: .incomplete))
        XCTAssertNil(BrowserBridgeResponsePolicy.status(parseResult: .accepted(draft)))
        XCTAssertEqual(BrowserBridgeResponsePolicy.status(parseResult: .badRequest), .badRequest)
        XCTAssertEqual(BrowserBridgeResponsePolicy.status(parseResult: .forbidden), .forbidden)
        XCTAssertEqual(BrowserBridgeResponsePolicy.status(parseResult: .methodNotAllowed), .methodNotAllowed)
        XCTAssertEqual(BrowserBridgeResponsePolicy.status(parseResult: .notFound), .notFound)
        XCTAssertEqual(BrowserBridgeResponsePolicy.status(parseResult: .payloadTooLarge), .payloadTooLarge)
    }

    private func headerPaddedToExactly4KiB(contentLength: Int) -> Data {
        let prefix = "POST /browser-event HTTP/1.1\r\nContent-Type: application/json\r\nX-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r\nContent-Length: \(contentLength)\r\nX-Fill: "
        let suffix = "\r\n\r\n"
        let fillLength = 4 * 1024 - prefix.utf8.count - suffix.utf8.count
        precondition(fillLength >= 0)
        return Data((prefix + String(repeating: "a", count: fillLength) + suffix).utf8)
    }
}
