//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

#include "Engine.hpp"

#include "Behaviors.hpp"
#include "Reveal.hpp"

namespace markdown {
namespace {

void appendDirty(std::vector<Range> &dirty, Offset offset) {
    if (!dirty.empty() && dirty.back().end() == offset) {
        dirty.back().length++;
    } else {
        dirty.push_back({offset, 1});
    }
}

/// Where `offset` ends up after `range` is replaced by `insertedLength` units.
Offset map(Offset offset, Range range, Offset insertedLength) {
    if (offset <= range.location) {
        return offset;
    }
    if (offset >= range.end()) {
        return offset - range.length + insertedLength;
    }
    return range.location + insertedLength;
}

} // namespace

Engine::Engine(std::u16string text, Options options) : document_(std::move(text)), options_(options) {
    parse_ = parse(document_);
    concealed_ = conceal(document_, parse_, selection_, options_.revealMode);
}

Engine::Style Engine::style(Offset offset) const {
    return {parse_.kinds[offset], parse_.depths[offset], concealed_[offset]};
}

Patch Engine::applyEdit(Range range, std::u16string_view replacement) {
    range = document_.clamp(range);
    Parse old = std::move(parse_);
    std::vector<uint8_t> oldConcealed = std::move(concealed_);
    auto oldStyle = [&](Offset offset) {
        return Style{old.kinds[offset], old.depths[offset], oldConcealed[offset]};
    };

    Offset inserted = static_cast<Offset>(replacement.size());
    document_.replace(range, replacement);
    Offset start = map(selection_.location, range, inserted);
    selection_ = {start, std::max(map(selection_.end(), range, inserted), start) - start};
    parse_ = parse(document_);
    concealed_ = conceal(document_, parse_, selection_, options_.revealMode);

    Patch patch;
    for (Offset offset = 0; offset < range.location; offset++) {
        if (style(offset) != oldStyle(offset)) {
            appendDirty(patch.dirty, offset);
        }
    }
    for (Offset offset = range.location; offset < range.location + inserted; offset++) {
        appendDirty(patch.dirty, offset);
    }
    for (Offset offset = range.location + inserted; offset < document_.length(); offset++) {
        if (style(offset) != oldStyle(offset - inserted + range.length)) {
            appendDirty(patch.dirty, offset);
        }
    }
    return patch;
}

Patch Engine::setSelection(Range selection) {
    selection_ = document_.clamp(selection);
    std::vector<uint8_t> concealed = conceal(document_, parse_, selection_, options_.revealMode);
    Patch patch;
    for (Offset offset = 0; offset < document_.length(); offset++) {
        if (concealed[offset] != concealed_[offset]) {
            appendDirty(patch.dirty, offset);
        }
    }
    concealed_ = std::move(concealed);
    return patch;
}

std::vector<Segment> Engine::segments(Range range) const {
    range = document_.clamp(range);
    std::vector<Segment> segments;
    for (Offset offset = range.location; offset < range.end(); offset++) {
        Style current = style(offset);
        if (!segments.empty() && offset > range.location && current == style(offset - 1)) {
            segments.back().range.length++;
            continue;
        }
        segments.push_back({{offset, 1}, current.kinds, current.depth, current.concealed != 0});
    }
    return segments;
}

std::vector<Element> Engine::elements(Range range) const {
    range = document_.clamp(range);
    std::vector<Element> elements;
    for (const auto &element : parse_.elements) {
        Range bounds = element.range;
        bool intersects = range.length == 0
            ? bounds.location <= range.location && range.location <= bounds.end()
            : bounds.location < range.end() && range.location < bounds.end();
        if (intersects) {
            elements.push_back(element);
        }
    }
    return elements;
}

std::optional<EditPlan> Engine::planNewline(Range selection) const {
    return markdown::planNewline(document_, parse_, selection);
}

std::optional<EditPlan> Engine::planTab(Range selection, bool backward) const {
    return markdown::planTab(document_, parse_, selection, backward);
}

std::optional<EditPlan> Engine::planBackspace(Range selection) const {
    return markdown::planBackspace(document_, parse_, selection);
}

std::optional<EditPlan> Engine::planToggleTask(Offset offset) const {
    return markdown::planToggleTask(parse_, offset);
}

std::optional<EditPlan> Engine::planToggleFormat(InlineFormat format, Range selection) const {
    return markdown::planToggleFormat(document_, parse_, format, selection);
}

} // namespace markdown
