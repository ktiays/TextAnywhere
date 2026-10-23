//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

#include "Behaviors.hpp"

#include "Characters.hpp"

#include <algorithm>
#include <string>

namespace markdown {
namespace {

bool isListBlock(BlockKind block) {
    return block == BlockKind::ListItem || block == BlockKind::Task;
}

bool isBlank(std::u16string_view text) {
    return std::all_of(text.begin(), text.end(), isWhitespace);
}

/// Adds one to a decimal number written as text, so arbitrarily long numbers keep their digits.
void increment(std::u16string &text, size_t start, size_t end) {
    size_t index = end;
    while (index > start) {
        index--;
        if (text[index] != u'9') {
            text[index]++;
            return;
        }
        text[index] = u'0';
    }
    text.insert(start, 1, u'1');
}

/// The prefix for the line after one starting with `prefix`: ordered markers count up and
/// tasks start unchecked.
std::u16string continuationPrefix(std::u16string prefix) {
    for (size_t index = prefix.size(); index > 0; index--) {
        char16_t unit = prefix[index - 1];
        if ((unit == u'.' || unit == u')') && index >= 2 && isASCIIDigit(prefix[index - 2])) {
            size_t end = index - 1;
            size_t start = end;
            while (start > 0 && isASCIIDigit(prefix[start - 1])) {
                start--;
            }
            increment(prefix, start, end);
            break;
        }
    }
    size_t checkbox = prefix.rfind(u'[');
    if (checkbox != std::u16string::npos && checkbox + 2 < prefix.size() && prefix[checkbox + 2] == u']') {
        prefix[checkbox + 1] = u' ';
    }
    return prefix;
}

/// Replaces `range` of `document` with `text`, trimmed to the span that actually changes.
EditPlan minimalPlan(const Document &document, Range range, const std::u16string &text, std::optional<Range> selectionAfter) {
    std::u16string_view old = document.substring(range);
    size_t prefix = 0;
    while (prefix < old.size() && prefix < text.size() && old[prefix] == text[prefix]) {
        prefix++;
    }
    size_t suffix = 0;
    while (suffix < old.size() - prefix && suffix < text.size() - prefix
           && old[old.size() - 1 - suffix] == text[text.size() - 1 - suffix]) {
        suffix++;
    }
    Range replace{range.location + static_cast<Offset>(prefix), static_cast<Offset>(old.size() - prefix - suffix)};
    return {replace, text.substr(prefix, text.size() - prefix - suffix), selectionAfter};
}

} // namespace

std::optional<EditPlan> planNewline(const Document &document, const Parse &parse, Range selection) {
    selection = document.clamp(selection);
    size_t index = document.lineIndex(selection.location);
    if (document.lineIndex(selection.end()) != index) {
        return std::nullopt;
    }
    const Line &line = document.lines()[index];
    const LineInfo &info = parse.lines[index];
    if (!isListBlock(info.block) && info.block != BlockKind::Quote) {
        return std::nullopt;
    }
    Offset bodyStart = line.start + info.prefixLength;
    if (info.prefixLength == 0 || selection.location < bodyStart) {
        return std::nullopt;
    }
    if (isBlank(document.substring({bodyStart, line.contentEnd - bodyStart}))) {
        return EditPlan{line.contentRange(), u"", Range{line.start, 0}};
    }
    std::u16string text = u"\n" + continuationPrefix(std::u16string(document.substring({line.start, info.prefixLength})));
    return EditPlan{selection, text, Range{selection.location + static_cast<Offset>(text.size()), 0}};
}

std::optional<EditPlan> planTab(const Document &document, const Parse &parse, Range selection, bool backward) {
    selection = document.clamp(selection);
    const auto &lines = document.lines();
    size_t first = document.lineIndex(selection.location);
    size_t last = document.lineIndex(selection.end());
    if (last > first && selection.end() == lines[last].start) {
        last--;
    }
    Range span{lines[first].start, lines[last].contentEnd - lines[first].start};

    std::u16string text;
    std::optional<Range> selectionAfter;
    Offset newSelectionStart = selection.location;
    Offset newSelectionEnd = selection.end();
    bool changes = false;
    for (size_t index = first; index <= last; index++) {
        const Line &line = lines[index];
        std::u16string_view content = document.content(line);
        Offset lineStart = span.location + static_cast<Offset>(text.size());
        std::u16string_view indentation;
        size_t removed = 0;
        if (isListBlock(parse.lines[index].block)) {
            if (!backward) {
                indentation = u"  ";
            } else if (content.starts_with(u"\t")) {
                removed = 1;
            } else {
                while (removed < 2 && removed < content.size() && content[removed] == u' ') {
                    removed++;
                }
            }
        }
        changes = changes || !indentation.empty() || removed > 0;
        auto map = [&](Offset position) {
            Offset offset = position - line.start;
            offset = backward ? offset - std::min<Offset>(offset, static_cast<Offset>(removed))
                              : offset + static_cast<Offset>(indentation.size());
            return lineStart + offset;
        };
        if (selection.location >= line.start && selection.location <= line.end) {
            newSelectionStart = map(std::min(selection.location, line.contentEnd));
        }
        if (selection.end() >= line.start && selection.end() <= line.contentEnd) {
            newSelectionEnd = map(selection.end());
        }
        text += indentation;
        text += content.substr(removed);
        if (index < last) {
            text += document.substring({line.contentEnd, line.end - line.contentEnd});
        }
    }
    if (!changes) {
        return std::nullopt;
    }
    selectionAfter = Range{newSelectionStart, std::max(newSelectionEnd, newSelectionStart) - newSelectionStart};
    return minimalPlan(document, span, text, selectionAfter);
}

std::optional<EditPlan> planBackspace(const Document &document, const Parse &parse, Range selection) {
    selection = document.clamp(selection);
    if (selection.length > 0) {
        return std::nullopt;
    }
    size_t index = document.lineIndex(selection.location);
    const Line &line = document.lines()[index];
    const LineInfo &info = parse.lines[index];
    bool hasBlockSyntax = isListBlock(info.block) || info.block == BlockKind::Quote || info.block == BlockKind::Heading;
    if (!hasBlockSyntax || info.prefixLength == 0 || selection.location != line.start + info.prefixLength) {
        return std::nullopt;
    }
    return EditPlan{{line.start, info.prefixLength}, u"", Range{line.start, 0}};
}

std::optional<EditPlan> planToggleTask(const Parse &parse, Offset offset) {
    const Element *task = nullptr;
    for (const auto &element : parse.elements) {
        if (element.kind == ElementKind::Task && element.range.location <= offset && offset <= element.range.end()) {
            task = &element;
        }
    }
    if (!task || task->markerRange.length != 3) {
        return std::nullopt;
    }
    return EditPlan{{task->markerRange.location + 1, 1}, task->checked ? u" " : u"x", std::nullopt};
}

std::optional<EditPlan> planToggleFormat(const Document &document, const Parse &parse, InlineFormat format, Range selection) {
    selection = document.clamp(selection);
    size_t line = document.lineIndex(selection.location);
    if (document.lineIndex(selection.end()) != line) {
        return std::nullopt;
    }

    KindSet kind = 0;
    std::u16string delimiter;
    switch (format) {
    case InlineFormat::Bold:
        kind = Strong;
        delimiter = u"**";
        break;
    case InlineFormat::Italic:
        kind = Emphasis;
        delimiter = u"*";
        break;
    case InlineFormat::Strikethrough:
        kind = Strikethrough;
        delimiter = u"~~";
        break;
    case InlineFormat::Code:
        kind = CodeSpan;
        delimiter = u"`";
        break;
    }

    const InlineSpan *enclosing = nullptr;
    for (const auto &span : parse.spans) {
        bool encloses = span.range.location <= selection.location && selection.end() <= span.range.end();
        if ((span.kinds & kind) && encloses && (!enclosing || span.range.length <= enclosing->range.length)) {
            enclosing = &span;
        }
    }
    if (enclosing) {
        Range content = enclosing->contentRange;
        auto map = [&](Offset position) {
            return enclosing->range.location + std::clamp(position, content.location, content.end()) - content.location;
        };
        Offset start = map(selection.location);
        return EditPlan{
            enclosing->range,
            std::u16string(document.substring(content)),
            Range{start, map(selection.end()) - start},
        };
    }

    Range target = selection;
    if (target.length == 0) {
        std::u16string_view text = document.text();
        const Line &bounds = document.lines()[line];
        Offset start = target.location;
        while (start > bounds.start && isWordCharacter(codePointBefore(text, start))) {
            start -= codePointBefore(text, start) > 0xFFFF ? 2 : 1;
        }
        Offset end = target.location;
        while (end < bounds.contentEnd && isWordCharacter(codePointAt(text, end))) {
            end += codePointAt(text, end) > 0xFFFF ? 2 : 1;
        }
        target = {start, end - start};
    }
    std::u16string_view text = document.substring(target);
    if (format == InlineFormat::Code) {
        size_t longest = 0;
        size_t run = 0;
        for (char16_t unit : text) {
            run = unit == u'`' ? run + 1 : 0;
            longest = std::max(longest, run);
        }
        delimiter = std::u16string(longest + 1, u'`');
    }
    Offset length = static_cast<Offset>(delimiter.size());
    Range selectionAfter = target.length == 0
        ? Range{target.location + length, 0}
        : Range{selection.location + length, selection.length};
    return EditPlan{target, delimiter + std::u16string(text) + delimiter, selectionAfter};
}

} // namespace markdown
