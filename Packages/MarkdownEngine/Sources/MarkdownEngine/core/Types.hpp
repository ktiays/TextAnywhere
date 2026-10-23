//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace markdown {

/// Offsets count UTF-16 code units, matching `NSString` and `NSRange`.
using Offset = uint32_t;

struct Range {
    Offset location = 0;
    Offset length = 0;

    Offset end() const { return location + length; }
    bool operator==(const Range &) const = default;
};

/// Semantic kinds of a piece of source. Kinds combine: bold text in a heading is
/// `Heading1 | Strong`, and its delimiters additionally carry `Marker`.
enum Kind : uint32_t {
    Heading1 = 1u << 0,
    Heading2 = 1u << 1,
    Heading3 = 1u << 2,
    Heading4 = 1u << 3,
    Heading5 = 1u << 4,
    Heading6 = 1u << 5,
    Strong = 1u << 6,
    Emphasis = 1u << 7,
    Strikethrough = 1u << 8,
    CodeSpan = 1u << 9,
    CodeBlock = 1u << 10,
    Link = 1u << 11,
    LinkURL = 1u << 12,
    Image = 1u << 13,
    Quote = 1u << 14,
    ListItem = 1u << 15,
    TaskItem = 1u << 16,
    TaskChecked = 1u << 17,
    Rule = 1u << 18,
    Table = 1u << 19,
    TableHeader = 1u << 20,
    Marker = 1u << 21,
};

using KindSet = uint32_t;

/// A maximal run of source with uniform styling. Segments cover the document without gaps
/// or overlaps. `depth` is the nesting level of the enclosing list item or quote.
struct Segment {
    Range range;
    KindSet kinds = 0;
    uint8_t depth = 0;
    bool concealed = false;
};

enum class ElementKind : uint8_t {
    Task,
    Link,
    CodeBlock,
    Quote,
    Rule,
    ListItem,
    Table,
};

/// A block or inline construct that decorations and interactions work with.
struct Element {
    ElementKind kind = ElementKind::ListItem;
    Range range;
    Range contentRange;
    /// The syntax that identifies the element: a list marker, a task's `[ ]`, a link's URL.
    Range markerRange;
    uint32_t depth = 0;
    bool ordered = false;
    uint64_t ordinal = 0;
    bool checked = false;
    uint32_t columnCount = 0;
    std::u16string url;
    std::u16string language;
};

/// Source ranges whose styling changed, in post-edit coordinates.
struct Patch {
    std::vector<Range> dirty;
};

/// An edit for the host to perform through its own undoable text system.
struct EditPlan {
    Range replace;
    std::u16string text;
    /// Where the selection goes afterwards. Empty means the host keeps its selection.
    std::optional<Range> selectionAfter;
};

enum class InlineFormat : uint8_t {
    Bold,
    Italic,
    Strikethrough,
    Code,
};

enum class RevealMode : uint8_t {
    /// Reveals the delimiters of each inline element that touches the selection.
    Element,
    /// Reveals every delimiter on the lines that the selection touches.
    Line,
};

struct Options {
    RevealMode revealMode = RevealMode::Element;
};

} // namespace markdown
