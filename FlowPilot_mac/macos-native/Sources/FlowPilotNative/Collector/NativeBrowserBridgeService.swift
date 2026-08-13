import FlowPilotNativeCore
import Foundation
import Network

@MainActor
final class NativeBrowserBridgeService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private let database: FlowPilotDatabase
    private var listener: NWListener?
    private var listenerGeneration = BrowserBridgeListenerGeneration()

    init(databaseURL: URL) {
        self.database = FlowPilotDatabase(path: databaseURL.path)
    }

    func start() {
        guard listener == nil else {
            return
        }

        do {
            guard let port = NWEndpoint.Port(rawValue: 17_321) else {
                lastError = "브라우저 브리지 포트를 열 수 없습니다."
                isRunning = false
                return
            }
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
            let listener = try NWListener(using: parameters)
            let generation = listenerGeneration.activate()
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self,
                          self.listenerGeneration.connectionDecision(for: generation) == .process else {
                        connection.cancel()
                        return
                    }
                    self.handle(connection, generation: generation)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.listenerGeneration.isCurrent(generation) else {
                        return
                    }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.lastError = nil
                    case .failed(let error):
                        self.listener = nil
                        self.isRunning = false
                        self.lastError = error.localizedDescription
                    case .waiting(let error):
                        self.isRunning = false
                        self.lastError = error.localizedDescription
                    case .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }
            self.listener = listener
            listener.start(queue: .global(qos: .utility))
        } catch {
            lastError = error.localizedDescription
            isRunning = false
        }
    }

    func stop() {
        listenerGeneration.invalidate()
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    func restart() {
        stop()
        lastError = nil
        start()
    }

    private nonisolated func handle(_ connection: NWConnection, generation: UInt64) {
        connection.start(queue: .global(qos: .utility))
        receive(on: connection, accumulated: Data(), generation: generation)
    }

    private nonisolated func receive(
        on connection: NWConnection,
        accumulated: Data,
        generation: UInt64
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024 + 4096) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            Task { @MainActor in
                guard self.listenerGeneration.connectionDecision(for: generation) == .process else {
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

                let parseResult = BrowserBridgeRequestParser.parse(next, isComplete: isComplete)
                switch parseResult {
                case .incomplete:
                    self.receive(on: connection, accumulated: next, generation: generation)
                case .accepted(let draft):
                    do {
                        try self.database.saveBrowserEvent(draft)
                        self.lastError = nil
                        let status = BrowserBridgeResponsePolicy.status(
                            parseResult: .accepted(draft),
                            persistenceSucceeded: true
                        ) ?? .internalServerError
                        self.send(status: status, on: connection)
                    } catch {
                        self.lastError = error.localizedDescription
                        let status = BrowserBridgeResponsePolicy.status(
                            parseResult: .accepted(draft),
                            persistenceSucceeded: false
                        ) ?? .internalServerError
                        self.send(status: status, on: connection)
                    }
                default:
                    guard let status = BrowserBridgeResponsePolicy.status(parseResult: parseResult) else {
                        self.send(status: .badRequest, on: connection)
                        return
                    }
                    self.send(status: status, on: connection)
                }
            }
        }
    }

    private nonisolated func send(status: BrowserBridgeHTTPStatus, on connection: NWConnection) {
        let response = "HTTP/1.1 \(status.rawValue) \(Self.reasonPhrase(for: status))\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private nonisolated static func reasonPhrase(for status: BrowserBridgeHTTPStatus) -> String {
        switch status {
        case .noContent: return "No Content"
        case .badRequest: return "Bad Request"
        case .forbidden: return "Forbidden"
        case .notFound: return "Not Found"
        case .methodNotAllowed: return "Method Not Allowed"
        case .payloadTooLarge: return "Payload Too Large"
        case .internalServerError: return "Internal Server Error"
        }
    }
}
