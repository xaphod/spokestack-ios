//
//  TextToSpeechDelegate.swift
//  Spokestack
//
//  Created by Noel Weichbrodt on 11/19/19.
//  Copyright © 2020 Spokestack, Inc. All rights reserved.
//

import Foundation

/// Protocol for receiving the response of a TTS request
@objc public protocol TextToSpeechDelegate: AnyObject {
    
    /// The TTS synthesis request has resulted in a successful response.
    /// - Note: The URL will be invalidated within 60 seconds of generation.
    /// - Parameter url: The url pointing to the TTS media container
    @objc optional func success(result: TextToSpeechResult) -> Void
    
    /// The TTS synthesis request has resulted in an error response.
    /// - Parameter error: The error representing the TTS response.
    @objc optional func failure(ttsError: Error) -> Void
    
    /// The TTS synthesis request has begun playback over the default audio system.
    @objc optional func didBeginSpeaking() -> Void
    
    /// The TTS synthesis request has finished playback.
    @objc optional func didFinishSpeaking() -> Void
    
    /// A trace event from the TTS system.
    /// - Parameter trace: The debugging trace message.
    @objc optional func didTrace(_ trace: String) -> Void
}
