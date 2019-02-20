//
//  Error.swift
//  SpokeStack
//
//  Created by Cory D. Wiles on 9/28/18.
//  Copyright © 2018 Pylon AI, Inc. All rights reserved.
//

import Foundation

public enum AudioError: Error {
    case general(String)
    case audioSessionSetup(String)
}

public enum SpeechPipelineError: Error {
    case illegalState(message: String)
}

public enum SpeechRecognizerError: Error {
    case unknownCause(String)
    case failed(String)
}