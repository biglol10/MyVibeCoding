import XCTest
@testable import MyMacCalendarCore

final class HolidayServiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    override func tearDown() {
        MockHolidayURLProtocol.handler = nil
        super.tearDown()
    }

    func testHiddenApiHolidayStaysHiddenAfterRefetch() throws {
        let newYear = HolidayImport(date: try date(2026, 1, 1), title: "New Year's Day", providerKey: "2026-01-01-New Year's Day")
        let hidden = HolidayRecord(date: try date(2026, 1, 1), title: "New Year's Day", source: .api, providerKey: "2026-01-01-New Year's Day", isHidden: true, year: 2026)

        let visible = HolidayMerger().merge(imports: [newYear], existing: [hidden], year: 2026)

        XCTAssertTrue(visible.isEmpty)
    }

    func testHiddenApiHolidayDateStaysHiddenWhenProviderRenamesIt() throws {
        let renamed = HolidayImport(
            date: try date(2026, 1, 1),
            title: "Renamed New Year",
            providerKey: "2026-01-01-Renamed New Year"
        )
        let hidden = HolidayRecord(
            date: try date(2026, 1, 1),
            title: "Old New Year",
            source: .api,
            providerKey: "2026-01-01-Old New Year",
            isHidden: true,
            year: 2026
        )

        let visible = HolidayMerger().merge(imports: [renamed], existing: [hidden], year: 2026)

        XCTAssertTrue(visible.isEmpty)
    }

    func testManualHolidayOverridesApiOnSameDate() throws {
        let api = HolidayImport(date: try date(2026, 5, 5), title: "Children's Day", providerKey: "2026-05-05-Children's Day")
        let manual = HolidayRecord(date: try date(2026, 5, 5), title: "어린이날 직접수정", source: .manual, year: 2026)

        let visible = HolidayMerger().merge(imports: [api], existing: [manual], year: 2026)

        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible[0].title, "어린이날 직접수정")
        XCTAssertEqual(visible[0].source, .manual)
    }

    func testImportPlannerReturnsOnlyNewApiDatesWithoutResponseDuplicates() throws {
        let existing = HolidayRecord(
            date: try date(2026, 1, 1),
            title: "새해",
            source: .api,
            providerKey: "2026-01-01-새해",
            year: 2026
        )
        let newHoliday = HolidayImport(
            date: try date(2026, 3, 1),
            title: "삼일절",
            providerKey: "2026-03-01-삼일절"
        )
        let imports = [
            HolidayImport(date: try date(2026, 1, 1), title: "New Year renamed", providerKey: "2026-01-01-New Year renamed"),
            newHoliday,
            newHoliday
        ]

        let records = HolidayImportPlanner(calendar: calendar).newRecords(
            imports: imports,
            existing: [existing],
            year: 2026
        )

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.providerKey, "2026-03-01-삼일절")
    }

    func testAutomaticRefreshPolicyFetchesOnlyMissingUnattemptedYear() {
        let policy = HolidayAutoRefreshPolicy()

        XCTAssertTrue(policy.shouldFetch(year: 2027, existingAPIYears: [2026], attemptedYears: []))
        XCTAssertFalse(policy.shouldFetch(year: 2027, existingAPIYears: [2027], attemptedYears: []))
        XCTAssertFalse(policy.shouldFetch(year: 2027, existingAPIYears: [], attemptedYears: [2027]))
        XCTAssertFalse(policy.shouldFetch(year: 0, existingAPIYears: [], attemptedYears: []))
    }

    func testNagerDecodeMapsLocalNameAndProviderKey() throws {
        let data = """
        [{"date":"2026-01-01","localName":"새해","name":"New Year's Day","countryCode":"KR","fixed":false,"global":true,"counties":null,"launchYear":null,"types":["Public"]}]
        """.data(using: .utf8)!

        let imports = try NagerHolidayDecoder().decode(data: data, calendar: calendar)

        XCTAssertEqual(imports.count, 1)
        XCTAssertEqual(imports[0].title, "새해")
        XCTAssertEqual(imports[0].providerKey, "2026-01-01-새해")
    }

    func testDecoderRejectsEntirePayloadWhenOneDateIsInvalid() throws {
        let data = """
        [
          {"date":"2026-01-01","localName":"새해"},
          {"date":"not-a-date","localName":"손상된 휴일"}
        ]
        """.data(using: .utf8)!

        XCTAssertThrowsError(try NagerHolidayDecoder().decode(data: data, calendar: calendar)) { error in
            XCTAssertEqual(error as? HolidayServiceError, .invalidResponse)
        }
    }

    func testMergerIgnoresImportsOutsideRequestedYear() throws {
        let imports = [
            HolidayImport(date: try date(2026, 1, 1), title: "새해", providerKey: "2026-01-01-새해"),
            HolidayImport(date: try date(2027, 1, 1), title: "다음 해", providerKey: "2027-01-01-다음 해")
        ]

        let records = HolidayMerger().merge(imports: imports, existing: [], year: 2026)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.providerKey, "2026-01-01-새해")
    }

    func testFetchRejectsHTTPErrorStatus() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockHolidayURLProtocol.self]
        let session = URLSession(configuration: configuration)
        MockHolidayURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )
            return (try XCTUnwrap(response), Data())
        }

        do {
            _ = try await HolidayService(session: session).fetchKoreanHolidays(year: 2026)
            XCTFail("Expected fetch to reject non-success HTTP status")
        } catch HolidayServiceError.badStatus(500) {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}

private final class MockHolidayURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
