//
//  ICECandidateMessage.swift
//  WebRTCSample
//
//  Created by Sergey Dunets on 6/27/18.
//  Copyright © 2018 Sergey Dunets. All rights reserved.
//

import Foundation

struct ICECandidateData: Codable {
    let candidate: String
    let sdpMid: String?
    let sdpMLineIndex: Int32
}

struct ICECandidateMessage: SignalingMessageProtocol, Codable {
    let type = SignalingMessageType.candidate
    let data: ICECandidateData
}
