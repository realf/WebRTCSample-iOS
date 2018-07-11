//
//  ViewController.swift
//  WebRTCSample
//
//  Created by Sergey Dunets on 6/18/18.
//  Copyright © 2018 Sergey Dunets. All rights reserved.
//

import UIKit
import Starscream
import WebRTC

@discardableResult func printLog(_ message: String = "", file: String = #file, line: Int = #line, function: String = #function) -> String {
    let log = ">>> [\(Date()) \(file):\(line) \(function)] \(message)"
    print(log)
    return log
}


extension UITextView {
    func scrollToBottom() {
        let rect = CGRect(x: 0, y: contentSize.height - 1, width: 1, height: 1)
        scrollRectToVisible(rect, animated: true)
    }
}

class ViewController: UIViewController, WebSocketDelegate, RTCPeerConnectionDelegate, RTCDataChannelDelegate {
    private var signalingSocket: WebSocket?
    
    // Replace with a real URL!
    private let host = "wss://example.com/api/connect"
    private var partnerId: String?
    private var isMaster: Bool?
    
    // The factory must be retained in a property to avoid a crash when trying to create the peer connection
    private let peerConnectionFactory = RTCPeerConnectionFactory(encoderFactory: nil, decoderFactory: nil)
    private let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var connectPartnerMessage: PairWithPartnerRequestMessage?
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()

    @IBOutlet weak var roomIDTextField: UITextField!
    @IBOutlet weak var messageTextField: UITextField!
    
    @IBOutlet weak var logTextView: UITextView! {
        willSet {
            // To enable automatic scrolling to the bottom
            newValue.layoutManager.allowsNonContiguousLayout = false
        }
    }
    
    @IBAction func tapSend(_ sender: Any) {
        guard let message = messageTextField.text else {
            return
        }
        
        messageTextField.text = ""
        send(message: message)
    }
    
    @IBAction func tapConnect(_ sender: Any) {
        connect()
    }
    
    @IBAction func tapDisconnect(_ sender: Any) {
        disconnect()
    }
    
    /// Validates room ID and connects to the signaling server
    private func connect() {
        let roomID = roomIDTextField.text
        if let roomID = roomID, roomID.count >= 5 && roomID.count <= 15 {
            let message = PairWithPartnerRequestMessage(roomId: roomID, reconnect: false)
            signalingConnect(message: message)
        } else {
            self.printToUI("Room ID should contain 5-15 characters.")
        }
    }
    
    private func disconnect() {
        dataChannel?.close()
        peerConnection?.close()
        dataChannel = nil
        peerConnection = nil
        
        signalingSocket?.delegate = nil
        signalingSocket?.disconnect()
        
        partnerId = nil
        isMaster = nil
        connectPartnerMessage = nil
        
        printToUI("Disconnected.")
    }
    
    /// Connects to signaling server with WebSocket
    private func signalingConnect(message: PairWithPartnerRequestMessage) {
        let socket = createSignalingSocket()
        signalingSocket = socket
        
        self.printToUI("Connecting to pairing server with websocket...")
        connectPartnerMessage = message
        socket.connect()
    }
    
    /// Sends 'pair' message to the signaling server
    private func handleSignalingDidConnect() {
        guard let pairMessage = try? jsonEncoder.encode(connectPartnerMessage) else {
            printLog("Cannot encode pair message")
            return
        }
        
        guard let socket = signalingSocket else {
            printLog("Signaling socket is nil")
            return
        }
        
        socket.write(data: pairMessage)
        self.printToUI("Signaling connected. Sent pair message.")
    }
    
    private func createSignalingSocket() -> WebSocket {
        let ws = WebSocket(url: URL(string: host)!)
        ws.delegate = self
        // Disable SSL certificate validation for debugging with MITM proxy, etc.
        // ws.disableSSLCertValidation = true
        return ws
    }
    
    /// Remote room is full (should be only 2 peers)
    private func handleRemoteFull() {
        // The room already has 2 peers. Disconnect.
        self.printToUI("Room is full, please try another one.")
        signalingSocket?.disconnect()
    }
    
    /// Remote partner connected
    private func handleRemotePair(message: PairWithPartnerBroadcastMessage) {
        partnerId = message.partnerId
        isMaster = message.mode == "master"
        printToUI("Remote partner \(message.partnerId) paired. I am in a \(message.mode) mode.")
        pair()
    }
    
    private func pair() {
        // Initiate peer connection
        let connection = createPeerConnection()
        self.peerConnection = connection
        printLog("Created peer connection object.")
        
        if let isMaster = isMaster, isMaster {
            dataChannel = connection.dataChannel(forLabel: "iOSMasterDataChannel", configuration: RTCDataChannelConfiguration())
            dataChannel?.delegate = self
            printToUI("Created data channel \(dataChannel!.label).")
            
            connection.offer(for: self.constraints, completionHandler: { [weak self] (description, error) in
                guard let `self` = self else {
                    return
                }
                
                self.peerConnection(connection, didCreateSessionDescription: description, error: error)
            })
        }
    }
    
    private func createPeerConnection() -> RTCPeerConnection {
        let config = RTCConfiguration()
        let peerConnection = peerConnectionFactory.peerConnection(with: config, constraints: constraints, delegate: self)
        return peerConnection
    }
    
    /// SDP Offer from master (received if you are in the slave mode) or answer from slave (if in the master mode)
    private func handleRemoteSessionDescription(message: SessionDescriptionMessage) {
        printLog()
        
        guard let connection = peerConnection else {
            printLog("No peer connection")
            return
        }
        
        connection.setRemoteDescription(message.sessionDescription, completionHandler: { [weak self] (error) in
            guard let `self` = self else {
                return
            }
            
            self.peerConnection(connection, didSetSessionDescriptionWithError: error)
        })
    }
    
    private func peerConnection(_ peerConnection: RTCPeerConnection, didSetSessionDescriptionWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else {
                return
            }
            
            guard error == nil else {
                printLog("Cannot set session description: \(error!)")
                // TODO: Disconnect
                return
            }
            
            if let isMaster = self.isMaster, !isMaster && peerConnection.localDescription == nil {
                peerConnection.answer(for: self.constraints, completionHandler: { [weak self] (sessionDescription, error) in
                    guard let `self` = self else {
                        return
                    }
                    
                    self.peerConnection(peerConnection, didCreateSessionDescription: sessionDescription, error: error)
                })
            }
        }
    }
    
    private func peerConnection(_ peerConnection: RTCPeerConnection, didCreateSessionDescription description: RTCSessionDescription?, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else {
                return
            }
            
            guard error == nil, let description = description else {
                printLog("Failed to create session description: \(error!)")
                // TODO: Disconnect
                return
            }
            
            peerConnection.setLocalDescription(description, completionHandler: { [weak self] error in
                guard let `self` = self else {
                    return
                }
                self.peerConnection(peerConnection, didSetSessionDescriptionWithError: error)
            })
            
            let sessionDescriptionMessage = SessionDescriptionMessage(description: description)
            guard let message = try? self.jsonEncoder.encode(sessionDescriptionMessage) else {
                printLog("Cannot encode session description message")
                return
            }
            
            guard let socket = self.signalingSocket else {
                printLog("No signaling socket")
                return
            }
            
            socket.write(data: message)
            self.printToUI("Sent SDP \(sessionDescriptionMessage.type).")
        }
    }
    
    /// New ICE Candidate delivered from the partner
    private func handleRemoteCandidate(message: ICECandidateMessage) {
        let candidate = RTCIceCandidate(sdp: message.data.candidate, sdpMLineIndex: message.data.sdpMLineIndex, sdpMid: message.data.sdpMid)
        peerConnection?.add(candidate)
        
        printLog("Added new ICE candidate: \(candidate)")
        printToUI("Added new ICE candidate.")
    }
    
    /// Sends message via WebRTC data channel
    private func send(message: String) {
        guard let dataChannel = dataChannel else {
            printLog("No data channel")
            return
        }
        
        guard dataChannel.readyState == .open else {
            printLog("Data channel is not ready")
            return
        }
        
        let buffer = RTCDataBuffer(data: message.data(using: .utf8)!, isBinary: false)
        dataChannel.sendData(buffer)
        printToUI("Sent message: '\(message)'.")
    }
    
    /// Prints message to log and UI
    private func printToUI(_ message: String = "", file: String = #file, line: Int = #line, function: String = #function) {
        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else {
                return
            }
            printLog(message, file: file, line: line, function: function)
            
            self.logTextView.text = self.logTextView.text.appending(message + "\n\n")
            self.logTextView.scrollToBottom()
        }
    }
    
    // MARK: - WebSocketDelegate
    
    func websocketDidConnect(socket: WebSocketClient) {
        printLog()
        handleSignalingDidConnect()
    }
    
    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        printLog("\(String(describing: error))")
        if error == nil {
            self.printToUI("Signalling WebSocket was closed. Trying to reconnect...")
            
            guard var connectPartnerMessage = connectPartnerMessage else {
                printLog("No pair message")
                return
            }
            
            connectPartnerMessage.reconnect = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let `self` = self else {
                    return
                }
                
                self.signalingConnect(message: connectPartnerMessage)
            }
        }
    }
    
    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        printLog("'\(text)'")
        let data = text.data(using: .utf8)!
        if let message = try? jsonDecoder.decode(SignalingMessage.self, from: data)  {
            self.printToUI("Received signaling message '\(message.type)'.")
            
            switch message.type {
            case .full:
                handleRemoteFull()
            
            case .pair:
                if let message = try? jsonDecoder.decode(PairWithPartnerBroadcastMessage.self, from: data) {
                    handleRemotePair(message: message)
                }
                
            case .offer:
                if let message = try? jsonDecoder.decode(SessionDescriptionMessage.self, from: data) {
                    handleRemoteSessionDescription(message: message)
                }
            
            case .answer:
                if let message = try? jsonDecoder.decode(SessionDescriptionMessage.self, from: data) {
                    handleRemoteSessionDescription(message: message)
                }
                
            case .candidate:
                if let message = try? jsonDecoder.decode(ICECandidateMessage.self, from: data) {
                    handleRemoteCandidate(message: message)
                }

            case .unpair:
                self.printToUI("Remote partner manually disconnected.")
            }
        }
    }
    
    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        self.printToUI("Websocket received data: '\(data)'.")
    }
    
    // MARK: - RTCPeerConnectionDelegate
    
    /**
     * Delegate methods below are called on signaling thread!
     */
    
    /** Called when the SignalingState changed. */
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        DispatchQueue.main.async {
            printLog("'\(stateChanged.rawValue)'")
        }
    }

    /** Called when media is received on a new stream from remote peer. */
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        DispatchQueue.main.async {
            printLog("'\(stream)'")
        }
    }

    /** Called when a remote peer closes a stream.
     *  This is not called when RTCSdpSemanticsUnifiedPlan is specified.
     */
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        DispatchQueue.main.async {
            printLog("'\(stream)'")
        }
    }
    
    /** Called when negotiation is needed, for example ICE has restarted. */
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        DispatchQueue.main.async {
            printLog()
        }
    }

    /** Called any time the IceConnectionState changes. */
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async {
            printLog("'\(newState.rawValue)'")
        }
    }
    
    /** Called any time the IceGatheringState changes. */
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        DispatchQueue.main.async {
            printLog("'\(newState.rawValue)'")
        }
    }
    
    /** New ice candidate has been found. */
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else {
                return
            }
            
            printLog("Received ICE candidate '\(candidate)'")
            
            let iceCandidateData = ICECandidateData(
                candidate: candidate.sdp,
                sdpMid: candidate.sdpMid,
                sdpMLineIndex: candidate.sdpMLineIndex
            )
            let iceCandidateRequest = ICECandidateMessage(data: iceCandidateData)
            guard let json = try? self.jsonEncoder.encode(iceCandidateRequest) else {
                printLog("Cannot encode ICE candidate message")
                return
            }
            
            guard let socket = self.signalingSocket else {
                printLog("No signaling socket")
                return
            }
            
            socket.write(data: json)
            self.printToUI("Sent an ICE candidate.")
        }
    }
    
    /** Called when a group of local Ice candidates have been removed. */
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        DispatchQueue.main.async {
            printLog("'\(candidates)'")
        }
    }
    
    /** New data channel has been opened. */
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else {
                return
            }
            self.printToUI("Opened data channel '\(dataChannel.label)'.")
            self.dataChannel = dataChannel
            self.dataChannel?.delegate = self
        }
    }
    
    // MARK: - RTCDataChannelDelegate
    
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        DispatchQueue.main.async {
            printLog("'\(dataChannel)'")
        }
    }
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        DispatchQueue.main.async {
            let message = String(data: buffer.data, encoding: .utf8)!
            self.printToUI("Received message: '\(message)'.")
        }
    }
}
