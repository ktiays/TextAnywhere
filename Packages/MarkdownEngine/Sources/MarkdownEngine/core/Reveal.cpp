//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

#include "Reveal.hpp"

namespace markdown {

std::vector<uint8_t> conceal(const Document &document, const Parse &parse, Range selection, RevealMode mode) {
    selection = document.clamp(selection);
    size_t firstLine = document.lineIndex(selection.location);
    size_t lastLine = document.lineIndex(selection.end());

    std::vector<uint8_t> isSpanRevealed(parse.spans.size(), 0);
    for (size_t index = 0; index < parse.spans.size(); index++) {
        Range range = parse.spans[index].range;
        isSpanRevealed[index] = range.location <= selection.end() && selection.location <= range.end();
    }

    std::vector<uint8_t> concealed(document.length(), 0);
    const auto &lines = document.lines();
    for (size_t line = 0; line < lines.size(); line++) {
        bool isLineRevealed = line >= firstLine && line <= lastLine;
        for (Offset offset = lines[line].start; offset < lines[line].contentEnd; offset++) {
            int32_t owner = parse.markers[offset];
            if (owner == BlockMarker) {
                concealed[offset] = !isLineRevealed;
            } else if (owner >= 0) {
                bool isRevealed = isSpanRevealed[owner] || (mode == RevealMode::Line && isLineRevealed);
                concealed[offset] = !isRevealed;
            }
        }
    }
    return concealed;
}

} // namespace markdown
