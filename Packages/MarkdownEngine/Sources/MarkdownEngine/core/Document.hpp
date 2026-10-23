//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

#pragma once

#include "Types.hpp"

#include <string>
#include <string_view>
#include <vector>

namespace markdown {

/// A physical line. `contentEnd` excludes the line break, `end` includes it.
struct Line {
    Offset start = 0;
    Offset contentEnd = 0;
    Offset end = 0;

    Range contentRange() const { return {start, contentEnd - start}; }
};

/// The Markdown source and its line table. Lines break at the same characters that end an
/// `NSString` paragraph, so block styling lines up with TextKit paragraphs.
class Document {
public:
    explicit Document(std::u16string text = {});

    const std::u16string &text() const { return text_; }
    Offset length() const { return static_cast<Offset>(text_.size()); }
    const std::vector<Line> &lines() const { return lines_; }

    /// The index of the line containing `offset`. The end of the text belongs to the last line.
    size_t lineIndex(Offset offset) const;
    std::u16string_view content(const Line &line) const;
    std::u16string_view substring(Range range) const;
    /// Limits `range` to the text so out-of-bounds input from the host is never trusted.
    Range clamp(Range range) const;

    void replace(Range range, std::u16string_view replacement);

private:
    void indexLines();

    std::u16string text_;
    std::vector<Line> lines_;
};

} // namespace markdown
