//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

#pragma once

#include "Document.hpp"
#include "Parser.hpp"
#include "Types.hpp"

#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace markdown {

/// Keeps the styling of a Markdown document current across edits and selection changes.
/// Every edit reparses the whole document; patches report exactly the units whose styling
/// changed, so the host only restyles those.
class Engine {
public:
    Engine(std::u16string text, Options options);

    const std::u16string &text() const { return document_.text(); }
    Offset length() const { return document_.length(); }

    Patch applyEdit(Range range, std::u16string_view replacement);
    /// Updates which syntax is revealed. The document isn't reparsed.
    Patch setSelection(Range selection);

    std::vector<Segment> segments(Range range) const;
    /// The elements that intersect `range`, or that contain it when it is empty.
    std::vector<Element> elements(Range range) const;

    std::optional<EditPlan> planNewline(Range selection) const;
    std::optional<EditPlan> planTab(Range selection, bool backward) const;
    std::optional<EditPlan> planBackspace(Range selection) const;
    std::optional<EditPlan> planToggleTask(Offset offset) const;
    std::optional<EditPlan> planToggleFormat(InlineFormat format, Range selection) const;

private:
    struct Style {
        KindSet kinds;
        uint8_t depth;
        uint8_t concealed;

        bool operator==(const Style &) const = default;
    };

    Style style(Offset offset) const;

    Document document_;
    Options options_;
    Parse parse_;
    std::vector<uint8_t> concealed_;
    Range selection_;
};

} // namespace markdown
