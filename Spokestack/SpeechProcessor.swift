//
//  SpeechProcessor.swift
//  Spokestack
//
//  Created by Noel Weichbrodt on 2/5/19.
//  Copyright © 2020 Spokestack, Inc. All rights reserved.
//

import Foundation

/// Protocol for speech pipeline components to receive speech pipeline coordination events.
///
/// `startStreaming` and `stopStreaming` are expected to be called repeatedly while the pipeline is running, and should respond to these functions by allocating and deallocating resources in order to optimize performance.
@objc public protocol SpeechProcessor: AnyObject {
    
    /// The global configuration for all speech pipeline components.
    @objc var configuration: SpeechConfiguration { get set }
    
    /// Global speech context.
    @objc var context: SpeechContext { get set }
    
    /// Trigger from the speech pipeline for the component to begin processing the audio stream.
    /// - Parameter context: The current speech context.
    @objc func startStreaming() -> Void
    
    /// Trigger from the speech pipeline for the component to stop processing the audio stream.
    @objc func stopStreaming() -> Void
    
    /// Receives a frame of audio samples for processing. Interface between the `SpeechProcessor` and `AudioController` components.
    /// - Parameter frame: Audio frame of samples.
    @objc func process(_ frame: Data) -> Void
}

/// Convenience enum for the singletons of the different implementers of the `SpeechProcessor` protocol.
internal enum SpeechProcessors: Int {
    /// AppleWakewordRecognizer
    case appleWakeword
    /// TFLiteWakewordRecognizer
    case tfLiteWakeword
    /// AppleSpeechRecognizer
    case appleSpeech
    /// WebRTCVAD
    case vad
    /// VADTrigger
    case vadTrigger
}

/// Profiles that may be passed to `SpeechPipelineBuilder` for easy pipeline configuring.
@objc public enum SpeechPipelineProfiles: Int {
    /// VAD-sensitive Apple wakeword activates Apple ASR
    case appleWakewordAppleSpeech
    /// VAD-sensitive TFLiteWakeword activates Apple ASR
    case tfLiteWakewordAppleSpeech
    /// VAD-triggered Apple ASR
    case vadTriggerAppleSpeech
    /// Apple ASR that is manually activated and deactivated
    case pushToTalkAppleSpeech
}

extension SpeechPipelineProfiles {
    /// Convenience property for getting a profile for use by `SpeechPipelineBuilder`.
    /// - Warning: Order is fixed for interop with React Native Spokestack. New profiles should be appended to end.
    internal var set: [SpeechProcessors]  {
        switch self {
        case .tfLiteWakewordAppleSpeech:
            return [.vad, .tfLiteWakeword, .appleSpeech]
        case .vadTriggerAppleSpeech:
            return [.vad, .vadTrigger, .appleSpeech]
        case .pushToTalkAppleSpeech:
            return [.appleSpeech]
        case .appleWakewordAppleSpeech:
            return [.vad, .appleWakeword, .appleSpeech]
        }
    }
}
