//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

#include "Document.hpp"

#include "Characters.hpp"

#include <algorithm>

namespace markdown {

Document::Document(std::u16string text) : text_(std::move(text)) {
    indexLines();
}

size_t Document::lineIndex(Offset offset) const {
    auto next = std::upper_bound(lines_.begin(), lines_.end(), offset, [](Offset value, const Line &line) {
        return value < line.start;
    });
    return static_cast<size_t>(std::distance(lines_.begin(), next)) - 1;
}

std::u16string_view Document::content(const Line &line) const {
    return substring(line.contentRange());
}

std::u16string_view Document::substring(Range range) const {
    return std::u16string_view(text_).substr(range.location, range.length);
}

Range Document::clamp(Range range) const {
    Offset location = std::min(range.location, length());
    return {location, std::min(range.length, length() - location)};
}

void Document::replace(Range range, std::u16string_view replacement) {
    range = clamp(range);
    text_.replace(range.location, range.length, replacement);
    indexLines();
}

void Document::indexLines() {
    lines_.clear();
    Offset start = 0;
    Offset index = 0;
    while (index < length()) {
        char16_t unit = text_[index];
        if (!isLineBreak(unit)) {
            index++;
            continue;
        }
        Offset contentEnd = index;
        index += unit == u'\r' && index + 1 < length() && text_[index + 1] == u'\n' ? 2 : 1;
        lines_.push_back({start, contentEnd, index});
        start = index;
    }
    lines_.push_back({start, length(), length()});
}

} // namespace markdown
