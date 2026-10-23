//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

#pragma once

#include <string_view>

namespace markdown {

inline bool isHighSurrogate(char16_t unit) { return unit >= 0xD800 && unit <= 0xDBFF; }

inline bool isLowSurrogate(char16_t unit) { return unit >= 0xDC00 && unit <= 0xDFFF; }

inline bool isLineBreak(char16_t unit) {
    return unit == u'\n' || unit == u'\r' || unit == 0x0085 || unit == 0x2029;
}

/// Whitespace as matched by `\s` in JavaScript, which the syntax rules were written against.
inline bool isWhitespace(char16_t unit) {
    switch (unit) {
    case u' ': case u'\t': case u'\n': case u'\v': case u'\f': case u'\r':
    case 0x00A0: case 0x1680: case 0x2028: case 0x2029: case 0x202F: case 0x205F: case 0x3000: case 0xFEFF:
        return true;
    default:
        return unit >= 0x2000 && unit <= 0x200A;
    }
}

inline bool isASCIIDigit(char16_t unit) { return unit >= u'0' && unit <= u'9'; }

/// The code point starting at `index`, or the lone surrogate itself when it is unpaired.
inline char32_t codePointAt(std::u16string_view text, size_t index) {
    char16_t unit = text[index];
    if (isHighSurrogate(unit) && index + 1 < text.size() && isLowSurrogate(text[index + 1])) {
        return 0x10000 + ((char32_t(unit) - 0xD800) << 10) + (char32_t(text[index + 1]) - 0xDC00);
    }
    return unit;
}

/// The code point ending just before `index`.
inline char32_t codePointBefore(std::u16string_view text, size_t index) {
    char16_t unit = text[index - 1];
    if (isLowSurrogate(unit) && index >= 2 && isHighSurrogate(text[index - 2])) {
        return codePointAt(text, index - 2);
    }
    return unit;
}

/// Approximates `[\p{L}\p{N}]` without Unicode tables: ASCII letters and digits, plus any
/// non-ASCII code point outside the common punctuation, symbol and emoji blocks.
inline bool isWordCharacter(char32_t codePoint) {
    if (codePoint < 0x80) {
        return (codePoint >= u'0' && codePoint <= u'9') || (codePoint >= u'a' && codePoint <= u'z')
            || (codePoint >= u'A' && codePoint <= u'Z');
    }
    if (codePoint <= 0xBF || (codePoint >= 0x2000 && codePoint <= 0x2BFF) || (codePoint >= 0x3000 && codePoint <= 0x303F)
        || (codePoint >= 0xD800 && codePoint <= 0xF8FF) || (codePoint >= 0xFE00 && codePoint <= 0xFE4F)
        || (codePoint >= 0xFF00 && codePoint <= 0xFF0F) || (codePoint >= 0xFF1A && codePoint <= 0xFF20)
        || (codePoint >= 0xFF3B && codePoint <= 0xFF40) || (codePoint >= 0xFF5B && codePoint <= 0xFF65)
        || (codePoint >= 0x1F000 && codePoint <= 0x1FAFF)) {
        return false;
    }
    return codePoint != 0xD7 && codePoint != 0xF7;
}

/// Code units that attach to the preceding character to form an emoji sequence, such as the
/// variation selector and keycap in `*️⃣`.
inline bool isEmojiJoiner(char16_t unit) {
    return unit == 0xFE0E || unit == 0xFE0F || unit == 0x20E3 || unit == 0x200D;
}

} // namespace markdown
