//
//  SignalingMessageProtocol.swift
//  WebRTCSample
//
//  Created by Sergey Dunets on 6/19/18.
//  Copyright © 2018 Sergey Dunets. All rights reserved.
//

import Foundation

enum SignalingMessageType: String, Codable {
    case full
    case pair
    case candidate
    case offer
    case answer
    case unpair
}

protocol SignalingMessageProtocol: Codable {
    var type: SignalingMessageType { get }
}

struct SignalingMessage: SignalingMessageProtocol {
    let type: SignalingMessageType
}
