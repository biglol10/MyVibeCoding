import FlowPilotNativeCore
import Foundation
import Network

@MainActor
final class NativeBrowserBridgeService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private let database: FlowPilotDatabase
    private var listener: NWListener?

    init(databaseURL: URL) {
        self.database = FlowPilotDatabase(path: databaseURL.path)
    }

    func start() {
        guard listener == nil else {
            return
        }

        do {
            let listener = try NWListener(using: .tcp, on: 17_321)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.lastError = nil
                    case .failed(let error):
                        self?.isRunning = false
                        self?.lastError = error.localizedDescription
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            listener.start(queue: .global(qos: .utility))
            self.listener = listener
        } catch {
            lastError = error.localizedDescription
            isRunning = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private nonisolated func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        receive(on: connection, accumulated: Data())
    }

    private nonisolated func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024 + 4096) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }

            var next = accumulated
            if let data {
                next.append(data)
            }

            if let response = Self.response(for: next) {
                if case .accepted(let draft) = response {
                    Task { @MainActor in
                        do {
                            try self.database.saveBrowserEvent(draft)
                            self.lastError = nil
                        } catch {
                            self.lastError = error.localizedDescription
                        }
                        self.send(response, on: connection)
                    }
                } else {
                    self.send(response, on: connection)
                }
                return
            }

            if isComplete {
                self.send(.badRequest, on: connection)
                return
            }

            self.receive(on: connection, accumulated: next)
        }
    }

    private nonisolated func send(_ response: BrowserBridgeHTTPResponse, on connection: NWConnection) {
        connection.send(content: response.data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private nonisolated static func response(for requestData: Data) -> BrowserBridgeHTTPResponse? {
        guard let request = String(data: requestData, encoding: .utf8) else {
            return .badRequest
        }
        guard let headerRange = request.range(of: "\r\n\r\n") else {
            return nil
        }

        let headerText = String(request[..<headerRange.lowerBound])
        let bodyText = String(request[headerRange.upperBound...])
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return .badRequest
        }

        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else {
            return .badRequest
        }
        guard requestParts[0] == "POST" else {
            return .methodNotAllowed
        }
        guard requestParts[1] == "/browser-event" else {
            return .notFound
        }

        let headers = Dictionary(
            uniqueKeysWithValues: lines.dropFirst().compactMap { line -> (String, String)? in
                guard let separator = line.firstIndex(of: ":") else {
                    return nil
                }
                let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
                return (name, value)
            }
        )

        guard headers["x-flowpilot-bridge"] == "flowpilot-browser-bridge-v1",
              headers["content-type"]?.split(separator: ";").first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "application/json" else {
            return .forbidden
        }

        if let contentLength = headers["content-length"].flatMap(Int.init),
           bodyText.utf8.count < contentLength {
            return nil
        }
        guard bodyText.utf8.count <= 16 * 1024 else {
            return .payloadTooLarge
        }
        guard let bodyData = bodyText.data(using: .utf8),
              let draft = try? JSONDecoder().decode(BrowserEventDraft.self, from: bodyData) else {
            return .badRequest
        }

        return .accepted(draft)
    }
}

private enum BrowserBridgeHTTPResponse {
    case accepted(BrowserEventDraft)
    case badRequest
    case forbidden
    case methodNotAllowed
    case notFound
    case payloadTooLarge

    var data: Data {
        let code: Int
        switch self {
        case .accepted:
            code = 204
        case .badRequest:
            code = 400
        case .forbidden:
            code = 403
        case .methodNotAllowed:
            code = 405
        case .notFound:
            code = 404
        case .payloadTooLarge:
            code = 413
        }

        return "HTTP/1.1 \(code) \(reasonPhrase(code))\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            .data(using: .utf8) ?? Data()
    }

    private func reasonPhrase(_ code: Int) -> String {
        switch code {
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        default: return "OK"
        }
    }
}
