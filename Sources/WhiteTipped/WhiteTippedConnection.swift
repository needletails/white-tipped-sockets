#if canImport(Network)
import Foundation
import Network
import ServiceLifecycle
import NeedleTailLogger
import WTHelpers
import NTKLoop

// Protocol defining methods for reporting connection state changes
protocol ConnectionStateDelegate: Sendable {
    func handleError(_ error: NWError?, closeCode: NWProtocolWebSocket.CloseCode?) async throws
    func startAutoPing(autoLoop: Bool) async
}

// Main actor managing WebSocket connections
public final actor WhiteTippedConnection: ConnectionStateDelegate {
    
    private let logger = NeedleTailLogger(.init(label: "[WebSocketConnectionManager]"))
    private let loop = NTKLoop()
    
    enum Errors: Error {
        case invalidText
    }
    
    public struct Configuration: @unchecked Sendable {
        let headers: [String: String]
        let cookies: [HTTPCookie]
        var urlRequest: URLRequest?
        let pingInterval: TimeInterval
        let connectionTimeout: Int
        let url: URL
        let trustAll: Bool
        let certificates: [String]
        let maxMessageSize: Int
        let autoReplyPing: Bool
        let queue: DispatchQueue
        
        public init(
            queueLabel: String,
            headers: [String: String] = [:],
            cookies: [HTTPCookie] = [],
            urlRequest: URLRequest? = nil,
            pingInterval: TimeInterval = 1.0,
            connectionTimeout: Int = 7,
            url: URL,
            trustAll: Bool,
            certificates: [String] = [],
            maxMessageSize: Int = 1_000_000 * 16,
            autoReplyPing: Bool = false
        ) {
            self.queue = DispatchQueue(label: queueLabel, attributes: .concurrent)
            self.headers = headers
            self.cookies = cookies
            self.urlRequest = urlRequest
            self.pingInterval = pingInterval
            self.connectionTimeout = connectionTimeout
            self.url = url
            self.trustAll = trustAll
            self.certificates = certificates
            self.maxMessageSize = maxMessageSize
            self.autoReplyPing = autoReplyPing
        }
    }
    
    // Service for monitoring viability of the connection
    actor ViabilityService: Service {
        let connection: NWConnection
        let receiver: MessageReceiver
        
        init(connection: NWConnection, receiver: MessageReceiver) {
            self.connection = connection
            self.receiver = receiver
        }
        
        func run() async throws {
            let stream = AsyncStream<Bool>(bufferingPolicy: .unbounded) { continuation in
                connection.viabilityUpdateHandler = { isViable in
                    continuation.yield(isViable)
                }
            }
            
            for try await isViable in stream {
                try await receiver.received(message: .viablePath(isViable))
            }
        }
    }
    
    // Service for monitoring better paths for the connection
    actor BetterPathService: Service {
        let connection: NWConnection
        let receiver: MessageReceiver
        
        init(connection: NWConnection, receiver: MessageReceiver) {
            self.connection = connection
            self.receiver = receiver
        }
        
        func run() async throws {
            let stream = AsyncStream<Bool>(bufferingPolicy: .unbounded) { continuation in
                connection.betterPathUpdateHandler = { hasBetterPath in
                    continuation.yield(hasBetterPath)
                }
            }
            
            for try await hasBetterPath in stream {
                try await receiver.received(message: .betterPath(hasBetterPath))
            }
        }
    }
    
    // Service for monitoring path updates
    actor PathUpdateService: Service {
        let connection: NWConnection
        let receiver: MessageReceiver
        
        init(connection: NWConnection, receiver: MessageReceiver) {
            self.connection = connection
            self.receiver = receiver
        }
        
        func run() async throws {
            let stream = AsyncStream<NWPath>(bufferingPolicy: .unbounded) { continuation in
                connection.pathUpdateHandler = { path in
                    continuation.yield(path)
                }
            }
            
            for try await path in stream {
                try await receiver.received(message: .pathStatus(path))
            }
        }
    }
    
    // Service for monitoring connection state
    actor ConnectionStateService: Service {
        let connection: NWConnection
        let receiver: MessageReceiver
        let timeout: TimeInterval
        let logger: NeedleTailLogger
        let delegate: ConnectionStateDelegate
        let loop = NTKLoop()
        
        init(
            connection: NWConnection,
            receiver: MessageReceiver,
            timeout: TimeInterval,
            logger: NeedleTailLogger,
            delegate: ConnectionStateDelegate) {
            self.connection = connection
            self.receiver = receiver
            self.timeout = timeout
            self.logger = logger
            self.delegate = delegate
        }
        
        func run() async throws {
            let stream = AsyncStream<NWConnection.State>(bufferingPolicy: .unbounded) { continuation in
                connection.stateUpdateHandler = { state in
                    continuation.yield(state)
                }
            }
            
            for try await state in stream {
                try await handleConnectionState(state)
            }
        }
        
        private func handleConnectionState(_ state: NWConnection.State) async throws {
            switch state {
            case .setup:
                logger.log(level: .info, message: "Connection setup")
            case .waiting(let error):
                logger.log(level: .info, message: "Connection waiting - \(error.localizedDescription)")
//                connection.restart()
            case .preparing:
                logger.log(level: .info, message: "Connection preparing")
                try await monitorConnectionPreparation()
            case .ready:
                logger.log(level: .info, message: "Connection established")
                try await receiveMessage()
            case .failed(let error):
                logger.log(level: .error, message: "Connection failed - \(error.localizedDescription)")
                try await receiver.received(message: .receivedError(error))
                try await delegate.handleError(error, closeCode: nil)
            case .cancelled:
                logger.log(level: .info, message: "Connection cancelled")
            default:
                logger.log(level: .info, message: "Connection state: \(state)")
            }
        }
        
        private func monitorConnectionPreparation() async throws {
            try await loop.run(timeout, sleep: .seconds(1)) {
                var canRun = true
                if self.connection.state == .ready {
                    canRun = false
                }
                return canRun
            }
            if self.connection.state != .ready {
                self.connection.stateUpdateHandler?(.failed(.posix(.ETIMEDOUT)))
            }
        }
        private func receiveMessage() async throws {
            let message = try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<WebSocketMessage, Error>) in
                connection.receiveMessage { content, context, isComplete, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        let message = WebSocketMessage(data: content, context: context, isComplete: isComplete)
                        continuation.resume(returning: message)
                    }
                }
            })
            try await processReceivedMessage(message)
        }
        
        private func processReceivedMessage(_ message: WebSocketMessage) async throws {
            guard let metadata = message.context?.protocolMetadata.first as? NWProtocolWebSocket.Metadata else { return }
            switch metadata.opcode {
            case .text:
                guard let data = message.data, let text = String(data: data, encoding: .utf8) else { return }
                try await receiver.received(message: .text(text))
            case .binary:
                if let data = message.data {
                    try await receiver.received(message: .binary(data))
                }
            case .close:
                try await delegate.handleError(nil, closeCode: metadata.closeCode)
            case .ping:
                try await receiver.received(message: .ping(Data()))
            case .pong:
                try await receiver.received(message: .pong(Data()))
                await delegate.startAutoPing(autoLoop: true)
            default:
                logger.log(level: .warning, message: "Unknown opcode: \(metadata.opcode)")
            }
        }
    }
    
    // Properties for the WebSocket connection
    public var configuration: Configuration
    private var connection: NWConnection
    private let receiver: MessageReceiver
    private var serviceGroup: ServiceGroup?
    
    public init(configuration: Configuration, receiver: MessageReceiver) throws {
        self.configuration = configuration
        self.receiver = receiver
        
        // Setup WebSocket options
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = configuration.autoReplyPing
        options.maximumMessageSize = configuration.maxMessageSize
        
        if let urlRequest = configuration.urlRequest {
            options.setAdditionalHeaders(urlRequest.allHTTPHeaderFields?.map { ($0.key, $0.value) } ?? [])
            for cookie in configuration.cookies {
                options.setAdditionalHeaders([(name: cookie.name, value: cookie.value)])
            }
        }
        
        if !configuration.headers.isEmpty {
            options.setAdditionalHeaders(configuration.headers.map { ($0.key, $0.value) })
        }
        
        let parameters: NWParameters = configuration.trustAll
        ? try TLSConfiguration.trustSelfSigned(configuration.trustAll, queue: configuration.queue, certificates: configuration.certificates)
        : (configuration.url.scheme == "ws" ? .tcp : .tls)
        
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        connection = NWConnection(to: .url(configuration.url), using: parameters)
    }
    
    deinit {
        logger.log(level: .trace, message: "WebSocketConnectionManager deallocated")
    }
    
    public func connect() async throws {
        connection.start(queue: configuration.queue)
        
        // Initialize and run services
        let services: [Service] = [
            ViabilityService(
                connection: connection,
                receiver: receiver),
            BetterPathService(
                connection: connection,
                receiver: receiver),
            PathUpdateService(
                connection: connection,
                receiver: receiver),
            ConnectionStateService(
                connection: connection,
                receiver: receiver,
                timeout: TimeInterval(configuration.connectionTimeout),
                logger: logger,
                delegate: self)
        ]
        serviceGroup = ServiceGroup(services: services, logger: .init(label: "[ServiceGroup]"))
        try await serviceGroup?.run()
    }
    
    public func shutdown() async throws {
        connection.cancel()
        await serviceGroup?.triggerGracefulShutdown()
    }
    
    // Methods for sending messages
    public func sendText(_ text: String) async throws {
        guard let data = text.data(using: .utf8) else { throw Errors.invalidText }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        try await self.send(data: data, context: context)
    }
    
    public func sendBinary(_ data: Data) async throws {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "binary", metadata: [metadata])
        try await self.send(data: data, context: context)
    }
    
    private func send(data: Data, context: NWConnection.ContentContext) async throws {
        try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                contentContext: context,
                isComplete: true,
                completion: .contentProcessed({ error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }))
        })
    }
    
    func sendPing() async throws {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .ping)
        try await self.pongHandler(metadata, queue: self.configuration.queue)
        let context = NWConnection.ContentContext(
            identifier: "ping",
            metadata: [metadata]
        )
        guard let data = "ping".data(using: .utf8) else { return }
        try await self.send(data: data, context: context)
    }
    
    func sendPong() async throws {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .pong)
        let context = NWConnection.ContentContext(
            identifier: "pong",
            metadata: [metadata]
        )
        guard let data = "pong".data(using: .utf8) else { return }
        try await self.send(data: data, context: context)
    }
    
    func pongHandler(_ metadata: NWProtocolWebSocket.Metadata, queue: DispatchQueue) async throws {
        try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<Void, Error>) in
            metadata.setPongHandler(queue) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        })
    }
    
    public func ping(autoLoop: Bool) async throws {
        if autoLoop {
            try await loop.run(.greatestFiniteMagnitude, sleep: .seconds(configuration.pingInterval)) { [weak self] in
                guard let self else { return false }
                var canRun = true
                if await connection.state != .ready {
                    canRun = false
                } else {
                    try await self.sendPing()
                }
                return canRun
            }
        } else {
            try await self.sendPing()
        }
    }
    
    public func pong(autoLoop: Bool) async throws {
        if autoLoop {
            try await loop.run(.greatestFiniteMagnitude, sleep: .seconds(configuration.pingInterval)) { [weak self] in
                guard let self else { return false }
                var canRun = true
                if await connection.state != .ready {
                    canRun = false
                } else {
                    try await self.sendPong()
                }
                return canRun
            }
        } else {
            try await self.sendPong()
        }
    }
    
    func handleError(_ error: NWError?, closeCode: NWProtocolWebSocket.CloseCode?) async throws {
        if let code = closeCode {
            switch code {
            case .protocolCode(let protocolCode):
                switch protocolCode {
                case .normalClosure, .protocolError:
                    //Close the connection and tell the client. A normal Closure occurs when the client expects to close the connection
                    //A protocolError indicates that some issue occured during the call andwe can no longer send events due to a non responsice socket so we will clean and close the connection.
                    try await self.receivedDisconnection(with: error, code)
                    self.connection.cancel()
                default:
                    let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
                    metadata.closeCode = code
                    let context = NWConnection.ContentContext(identifier: "close", metadata: [metadata])
                    try await self.send(data: Data(), context: context)
                    try await self.receivedDisconnection(with: error, code)
                    self.connection.cancel()
                }
            default:
                try await self.receivedDisconnection(code)
                self.connection.cancel()
            }
        } else {
            //No WebSocket Protocol Code, meaning we received some unexpected error from the server side
            try await self.receivedDisconnection()
            self.connection.cancel()
        }
    }
    
    func receivedDisconnection(with error: NWError? = nil, _ reason: NWProtocolWebSocket.CloseCode? = nil) async throws {
        let result = DisconnectResult(error: error, code: reason)
        try await self.receiver.received(message: .disconnectPacket(result))
    }
    
    func startAutoPing(autoLoop: Bool) async {
        do {
            try await ping(autoLoop: autoLoop)
        } catch {
            logger.log(level: .error, message: "\(error)")
        }
    }
}
#endif
