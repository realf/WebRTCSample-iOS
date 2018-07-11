//
//  SessionDescriptionMessage.swift
//  WebRTCSample
//
//  Created by Sergey Dunets on 6/27/18.
//  Copyright © 2018 Sergey Dunets. All rights reserved.
//

import Foundation
import WebRTC

struct SessionDescriptionMessage: SignalingMessageProtocol {
    struct SessionDescriptionData: Codable {
        enum WebRTCMessageType: String, Codable {
            case offer
            case answer
        }
        
        let type: WebRTCMessageType
        let sdp: String
        
        init(description: RTCSessionDescription) {
            self.sdp = description.sdp
            
            switch description.type {
            case .answer:
                self.type = .answer
                
            case .offer:
                self.type = .offer
                
            case .prAnswer:
                fatalError("Not supported type \(description.type)")
            }
        }
    }
    
    let type: SignalingMessageType
    let data: SessionDescriptionData
    
    var sessionDescription: RTCSessionDescription {
        let sdp = self.data.sdp
        let rtcType: RTCSdpType
        
        switch self.data.type {
        case .answer:
            rtcType = .answer
            
        case .offer:
            rtcType = .offer
        }
        
        return RTCSessionDescription(type: rtcType, sdp: sdp)
    }
    
    init(description: RTCSessionDescription) {
        self.data = SessionDescriptionData(description: description)
        switch description.type {
        case .answer:
            self.type = .answer
            
        case .offer:
            self.type = .offer
            
        case .prAnswer:
            fatalError("Not supported type \(description.type)")
        }
    }
}
