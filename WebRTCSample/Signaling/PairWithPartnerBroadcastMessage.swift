//
//  PairWithPartnerBroadcastMessage.swift
//  WebRTCSample
//
//  Created by Sergey Dunets on 6/19/18.
//  Copyright © 2018 Sergey Dunets. All rights reserved.
//

import Foundation

struct PairWithPartnerBroadcastMessage: SignalingMessageProtocol, Decodable {
    let type = SignalingMessageType.pair
    let partnerId: String
    let mode: String
    let reconnect: Bool?
}
