//
//  SpeechOutput.swift
//  MicDrop
//
//  Query-type commands ("what's on my calendar") get spoken aloud, not
//  pasted at the cursor — pasting "3 events today..." into whatever text
//  field happens to be focused would be actively wrong. Action-type
//  commands (opening an app, setting a timer) just get a notification.
//

import AVFoundation

struct SpeechOutput {
    private static let synthesizer = AVSpeechSynthesizer()

    static func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
}
