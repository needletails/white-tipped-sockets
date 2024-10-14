//
//  WhiteTippedReciever.swift
//  
//
//  Created by Cole M on 6/16/22.
//
#if canImport(Network) && canImport(Combine) && canImport(SwiftUI)
import Foundation
@preconcurrency import Network

public struct DisconnectResult: Sendable {
    public var error: NWError?
    public var code: NWProtocolWebSocket.CloseCode?
}

public enum MessagePacket {
    case text(String)
    case binary(Data)
    case ping(Data)
    case pong(Data)
    case betterPath(Bool)
    case viablePath(Bool)
    case pathStatus(NWPath)
    case receivedError(Error)
    case disconnectPacket(DisconnectResult)
}

public protocol MessageReceiver: AnyObject, Sendable {
    func received(message packet: MessagePacket) async throws
}
public extension MessageReceiver {
    func received(message packet: MessagePacket) async throws {}
}
#endif
