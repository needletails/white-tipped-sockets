#if canImport(Network)
import Testing
import Foundation
@testable import WhiteTipped
@testable import WTHelpers

final class WhiteTippedTests: @unchecked Sendable, MessageReceiver {
    
    var socket: WhiteTippedConnection!
    weak var delegate: MessageReceiver?
    
    func setUp() async throws {
        guard let url = URL(string: "ws://127.0.0.1:8083/connect-to-my-vapor-endpoint") else { return }
        
        socket = try WhiteTippedConnection(
            configuration: WhiteTippedConnection.Configuration(
                queueLabel: "connection",
                pingInterval: 5,
                connectionTimeout: 7,
                url: url,
                trustAll: false
            ),
            receiver: self
        )
        
        delegate = self
        try await self.socket.connect()
    }
    
    func tearDown() async throws {
        try await socket.shutdown()
    }
    
    @Test
    func testSendText() async throws {
        do {
            try await setUp()
            try await withThrowingTaskGroup(of: Void.self, body: { group in
                try Task.checkCancellation()
                group.addTask {
                    try await self.socket.sendText("WebSockets")
                }
                _ = try await group.next()
                group.cancelAll()
            })
            try await tearDown()
        } catch {
            try await tearDown()
        }
    }
    
    func createTotalParts(_ message: String) async -> Int {
        return (message.count / 700) + 1
    }
    
    struct MultipartPacket: Codable {
        var id: Int
        var finalId: Int
        var message: String
    }
    
    @Test
    func testSendBinary() async throws {
        try await setUp()
        try await withThrowingTaskGroup(of: Void.self, body: { group in
            try Task.checkCancellation()
            group.addTask {
                let bytes: [UInt8] = [12, 12, 34, 55, 66, 77]
                let d = Data(bytes)
                try await self.socket.sendBinary(d)
            }
            _ = try await group.next()
            group.cancelAll()
        })
        try await tearDown()
    }
    
    @Test
    func testSendPing() async throws {
        try await setUp()
        try await self.socket.sendPing()
        try await tearDown()
    }
    
    @Test
    func testSendPong() async throws {
        try await setUp()
        try await self.socket.sendPong()
        try await tearDown()
    }
    
    @Test
    func testReceivedFromServer() async throws {
        try await setUp()
        try await self.delegate?.received(message: MessagePacket.text("RECEIVED_TEXT"))
        try await tearDown()
    }

    func received(message packet: MessagePacket) async throws {
        switch packet {
        case .pong(let data):
            #expect(data != nil)
        case .text(let text):
            if text == "RECEIVED_TEXT" {
                #expect(text != "RECEIVED_TEXT")
            } else {
                #expect(text != "WebSockets")
            }
        case .binary(let data):
            #expect(data.bytes != [12, 12, 34, 55, 66, 77])
        case .ping(let data):
            #expect(data != nil)
        case .betterPath(_):
            break
        case .viablePath(_):
            break
        case .pathStatus(_):
            break
        case .disconnectPacket(_):
            break
        case .receivedError(_):
            try await tearDown()
        }
    }
}
#endif
enum DecodeError: Error {
    case couldntDecode
}
extension JSONDecoder {
    func decodeString<T: Codable>(_ type: T.Type, from string: String) throws -> T {
        guard let data = string.data(using: .utf8) else { throw DecodeError.couldntDecode }
        let object = try self.decode(type, from: data)
        return object
    }
}
extension Data {
    internal var bytes: [UInt8] {
        return [UInt8](self)
    }
}


let longMessage = """
Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Amet nisl purus in mollis nunc sed. Dignissim suspendisse in est ante in nibh mauris. Tincidunt id aliquet risus feugiat in ante. Commodo ullamcorper a lacus vestibulum. Est ullamcorper eget nulla facilisi etiam dignissim diam quis. Phasellus egestas tellus rutrum tellus. Eu lobortis elementum nibh tellus molestie nunc. Ornare lectus sit amet est. Iaculis urna id volutpat lacus laoreet non curabitur gravida arcu. Phasellus faucibus scelerisque eleifend donec. Donec ultrices tincidunt arcu non sodales. Dui ut ornare lectus sit amet est. Etiam tempor orci eu lobortis elementum.

Consectetur adipiscing elit pellentesque habitant morbi tristique senectus et. Adipiscing vitae proin sagittis nisl rhoncus. Quam adipiscing vitae proin sagittis nisl rhoncus mattis. Amet nisl suscipit adipiscing bibendum est ultricies integer quis auctor. Lorem dolor sed viverra ipsum nunc aliquet bibendum enim. Nec dui nunc mattis enim ut. Etiam erat velit scelerisque in dictum non consectetur. Sit amet porttitor eget dolor morbi non arcu. Quisque egestas diam in arcu cursus euismod quis. Mi ipsum faucibus vitae aliquet nec ullamcorper sit amet risus. Vestibulum lectus mauris ultrices eros. Arcu bibendum at varius vel pharetra vel turpis nunc. Sed turpis tincidunt id aliquet risus feugiat in ante. Varius duis at consectetur lorem donec massa. Ullamcorper morbi tincidunt ornare massa eget egestas purus viverra accumsan. Egestas erat imperdiet sed euismod nisi porta lorem mollis. Sit amet volutpat consequat mauris nunc. Sed adipiscing diam donec adipiscing tristique risus nec feugiat. Risus ultricies tristique nulla aliquet enim tortor at. Dolor purus non enim praesent elementum facilisis leo vel.

Etiam dignissim diam quis enim lobortis scelerisque fermentum dui. Mattis vulputate enim nulla aliquet. Mi in nulla posuere sollicitudin aliquam ultrices sagittis orci. Odio aenean sed adipiscing diam donec. Praesent elementum facilisis leo vel fringilla est ullamcorper. Morbi tristique senectus et netus et malesuada fames ac turpis. Non tellus orci ac auctor augue mauris. Sodales ut eu sem integer vitae justo. Parturient montes nascetur ridiculus mus mauris vitae ultricies leo. Ornare arcu odio ut sem nulla. Ultricies leo integer malesuada nunc vel risus. Quis varius quam quisque id diam. Vel facilisis volutpat est velit egestas dui. Egestas pretium aenean pharetra magna ac placerat vestibulum lectus. Enim sit amet venenatis urna cursus. Nullam non nisi est sit amet facilisis magna etiam. Sit amet tellus cras adipiscing enim. Senectus et netus et malesuada fames ac. Lacus laoreet non curabitur gravida arcu.

Viverra mauris in aliquam sem fringilla ut morbi. Dignissim convallis aenean et tortor at. Amet purus gravida quis blandit turpis cursus in. Mattis rhoncus urna neque viverra justo nec ultrices dui sapien. Consectetur adipiscing elit duis tristique sollicitudin. Id interdum velit laoreet id donec ultrices tincidunt arcu. Bibendum neque egestas congue quisque egestas diam in arcu cursus. Aliquet eget sit amet tellus cras adipiscing enim eu turpis. Diam vel quam elementum pulvinar etiam non. Maecenas sed enim ut sem viverra aliquet eget. Arcu odio ut sem nulla pharetra diam. Viverra tellus in hac habitasse platea dictumst vestibulum rhoncus est. Tellus mauris a diam maecenas sed enim ut sem. Amet venenatis urna cursus eget. Magna fringilla urna porttitor rhoncus dolor purus non enim. Elementum tempus egestas sed sed. Sed viverra tellus in hac habitasse platea.

Amet nisl purus in mollis nunc sed id semper. Consequat ac felis donec et odio pellentesque diam. Amet consectetur adipiscing elit duis tristique sollicitudin nibh sit. Enim tortor at auctor urna nunc id cursus metus aliquam. Tortor id aliquet lectus proin nibh nisl condimentum id venenatis. Diam ut venenatis tellus in. Aenean vel elit scelerisque mauris. In dictum non consectetur a erat nam at lectus urna. Viverra accumsan in nisl nisi scelerisque eu. Nibh venenatis cras sed felis eget velit aliquet sagittis. Tristique senectus et netus et. Ullamcorper dignissim cras tincidunt lobortis.
"""
