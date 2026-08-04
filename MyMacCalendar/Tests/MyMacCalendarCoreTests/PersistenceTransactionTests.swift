import XCTest
@testable import MyMacCalendarCore

final class PersistenceTransactionTests: XCTestCase {
    func testSaveFailureRollsBackBeforeRethrowing() {
        let context = FailingPersistenceContext()

        XCTAssertThrowsError(try PersistenceTransaction.save(context: context)) { error in
            XCTAssertTrue(error is TestSaveError)
        }
        XCTAssertEqual(context.operations, ["save", "rollback"])
    }

    func testSuccessfulSaveDoesNotRollback() throws {
        let context = SuccessfulPersistenceContext()

        try PersistenceTransaction.save(context: context)

        XCTAssertEqual(context.operations, ["save"])
    }

    func testExternalStateIsCompensatedWhenLocalSaveFails() {
        var externalValues: [Bool] = []
        var localValues: [Bool] = []
        let context = FailingPersistenceContext()

        XCTAssertThrowsError(
            try ExternalStateTransaction.apply(
                previous: false,
                desired: true,
                applyExternal: { externalValues.append($0) },
                mutateLocal: { localValues.append($0) },
                saveLocal: { try PersistenceTransaction.save(context: context) }
            )
        )

        XCTAssertEqual(externalValues, [true, false])
        XCTAssertEqual(localValues, [true])
        XCTAssertEqual(context.operations, ["save", "rollback"])
    }

    func testCompensationFailurePreservesBothErrors() {
        var externalValues: [Bool] = []

        XCTAssertThrowsError(
            try ExternalStateTransaction.apply(
                previous: false,
                desired: true,
                applyExternal: { value in
                    externalValues.append(value)
                    if value == false { throw TestCompensationError.failed }
                },
                mutateLocal: { _ in },
                saveLocal: { throw TestSaveError.failed }
            )
        ) { error in
            guard let combined = error as? ExternalStateCompensationError else {
                return XCTFail("Expected compensation error")
            }
            XCTAssertTrue(combined.persistenceError is TestSaveError)
            XCTAssertTrue(combined.compensationError is TestCompensationError)
        }

        XCTAssertEqual(externalValues, [true, false])
    }
}

private enum TestSaveError: Error {
    case failed
}

private enum TestCompensationError: Error {
    case failed
}

private final class FailingPersistenceContext: PersistenceContext {
    var operations: [String] = []

    func save() throws {
        operations.append("save")
        throw TestSaveError.failed
    }

    func rollback() {
        operations.append("rollback")
    }
}

private final class SuccessfulPersistenceContext: PersistenceContext {
    var operations: [String] = []

    func save() throws {
        operations.append("save")
    }

    func rollback() {
        operations.append("rollback")
    }
}
