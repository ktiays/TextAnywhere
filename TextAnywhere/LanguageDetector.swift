//
// Created by ktiays on 2026/10/22.
// Copyright (c) 2026 ktiays. All rights reserved.
//

import Foundation
import NaturalLanguage

enum LanguageDetector {

    private static let sampleLength = 1_000

    /// Returns the base language code of the dominant language in `text`,
    /// or `nil` when the language can't be recognized.
    static func languageCode(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(recognitionText(for: String(text.prefix(sampleLength))))
        guard let language = recognizer.dominantLanguage, language != .undetermined else {
            return nil
        }
        return TranslationLanguage.baseLanguageCode(for: language.rawValue)
    }

    /// The recognizer weighs every letter equally, so a few Latin terms embedded in CJK text
    /// (for example "我在用 Xcode 写 SwiftUI") can outvote the CJK characters. When CJK characters
    /// outnumber Latin words, only the non-Latin part of the text is recognized.
    private static func recognitionText(for text: String) -> String {
        var cjkCharacterCount = 0
        var latinWordCount = 0
        var isInLatinWord = false
        var nonLatinScalars = String.UnicodeScalarView()

        for scalar in text.unicodeScalars {
            let isLatinLetter = scalar.properties.isAlphabetic && scalar.value < 0x0250
            if isLatinLetter {
                if !isInLatinWord {
                    latinWordCount += 1
                }
                isInLatinWord = true
                continue
            }
            isInLatinWord = false
            if isCJK(scalar) {
                cjkCharacterCount += 1
            }
            nonLatinScalars.append(scalar)
        }

        return cjkCharacterCount > latinWordCount ? String(nonLatinScalars) : text
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x31F0...0x31FF, 0xAC00...0xD7AF:
            true
        default:
            scalar.properties.isIdeographic
        }
    }
}
