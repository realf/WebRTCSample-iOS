//
//  PairWithPartnerRequestMessage.swift
//  WebRTCSample
//
//  Created by Sergey Dunets on 6/19/18.
//  Copyright © 2018 Sergey Dunets. All rights reserved.
//

import Foundation

struct PairWithPartnerRequestMessage: SignalingMessageProtocol, Encodable {
    let type = SignalingMessageType.pair
    let clientId = "ios"
    let roomId: String
    var reconnect: Bool
}
