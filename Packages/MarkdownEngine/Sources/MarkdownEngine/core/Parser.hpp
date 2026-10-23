//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

#pragma once

#include "Document.hpp"
#include "Types.hpp"

#include <vector>

namespace markdown {

/// The block a line belongs to, as far as editing behaviors are concerned.
enum class BlockKind : uint8_t {
    Paragraph,
    Heading,
    Quote,
    ListItem,
    Task,
    Rule,
    Code,
    Table,
};

struct LineInfo {
    BlockKind block = BlockKind::Paragraph;
    /// Length of the block syntax at the start of the line, such as `> - [ ] `.
    Offset prefixLength = 0;
};

/// An inline construct whose delimiters are concealed and revealed together.
struct InlineSpan {
    Range range;
    Range contentRange;
    /// `Strong`, `Emphasis`, `Strikethrough`, `CodeSpan` or `Link`; empty for other syntax
    /// such as a backslash escape.
    KindSet kinds = 0;
};

/// Who owns the marker at a code unit, so the reveal policy can decide whether it shows.
/// Non-negative values index `Parse::spans`.
enum MarkerOwner : int32_t {
    NotMarker = -1,
    BlockMarker = -2,
    /// Syntax that is styled as a marker but never concealed, such as table pipes.
    VisibleMarker = -3,
};

struct Parse {
    std::vector<KindSet> kinds;
    std::vector<uint8_t> depths;
    std::vector<int32_t> markers;
    std::vector<InlineSpan> spans;
    std::vector<LineInfo> lines;
    /// Sorted by location, enclosing elements before the elements they contain.
    std::vector<Element> elements;
};

/// Parses the document with md4c and maps its output back onto the source.
Parse parse(const Document &document);

} // namespace markdown
