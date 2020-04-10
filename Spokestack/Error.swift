//
//  Error.swift
//  Spokestack
//
//  Created by Cory D. Wiles on 9/28/18.
//  Copyright © 2020 Spokestack, Inc. All rights reserved.
//

import Foundation

/// Errors thrown by `AudioController` during `startStreaming` and `stopStreaming`.
/// - SeeAlso: AudioController
public enum AudioError: Error, Equatable {
    /// An audio unit system error
    case audioSessionSetup(String)
}

/// Errors thrown by the `SpeechPipeline`.
/// - SeeAlso: SpeechPipeline
public enum SpeechPipelineError: Error, Equatable {
    /// The SpeechPipeline internal buffers entered an illegal state.
    case illegalState(String)
}

/// Errors thrown by the Voice Activity Detector.
public enum VADError: Error, Equatable {
    /// The VAD instance was configured with incompatible settings.
    case invalidConfiguration(String)
    /// The VAD instance was unable to initialize.
    case initialization(String)
    /// The VAD instance encountered an error during the processing of the audio frame.
    case processing(String)
}

/// Errors thrown by implementors of the WakewordRecognizer protocol.
public enum WakewordModelError: Error, Equatable {
    /// The WakewordRecognizer was unable to configure the recognizer model(s).
    case model(String)
    /// The WakewordRecognizer encountered an error during the processing of the audio frame.
    case process(String)
    /// The WakewordRecognizer encountered an error during the configuration or running of the filter model.
    case filter(String)
    /// The WakewordRecognizer encountered an error during the configuration or running of the encode model.
    case encode(String)
    /// The WakewordRecognizer encountered an error during the configuration or running of the detect model.
    case detect(String)
}

/// Errors thrown by RingBuffer instances.
enum RingBufferStateError: Error {
    // The RingBuffer instance entered an illegal state during a `read` or `write`.
    case illegalState(message: String)
}

/// Errors thrown by TTS instances.
enum TextToSpeechErrors: Error {
    /// The synthesize response was missing data.
    case deserialization(String)
    /// The synthesize request was unable to be serialized.
    case serialization(String)
    /// The api key provided is not valid.
    case apiKey(String)
    /// The speak command could not be executed.
    case speak(String)
    /// The input format was not specified correctly
    case format(String)
    /// The input voice was not specified correctly
    case voice(String)
}

/// Errors thrown by a Tokenizer instance.
enum TokenizerError: Error {
    /// The text to tokenize is too long.
    case tooLong(String)
    /// The tokenizer instance was configured with incompatible settings.
    case invalidConfiguration(String)
}

/// Errors thrown by an NLUService instance.
public enum NLUError: Error {
    /// The NLUService instance was configured with incompatible settings.
    case invalidConfiguration(String)
    /// The NLUService tokenizer encountered an error.
    case tokenizer(String)
    /// The model provided to the NLUService instance encountered an error.
    case model(String)
    /// There was a problem with the metadata provided to the NLUService instance.
    case metadata(String)
}
