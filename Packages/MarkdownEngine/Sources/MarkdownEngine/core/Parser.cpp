//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

#include "Parser.hpp"

#include "Characters.hpp"

#include <md4c.h>

#include <algorithm>
#include <optional>
#include <string>
#include <string_view>

// md4c reports structure but not source positions. Its text callbacks, however, point into the
// input buffer, so every source character that md4c doesn't emit as text is syntax. The parser
// records md4c's events, then walks the gaps between text runs and attributes their characters:
// span delimiters sit next to the text they enclose, block syntax precedes a line's text, and
// lines without any text are matched against the block events that occurred around them.

namespace markdown {
namespace {

constexpr unsigned parserFlags = MD_FLAG_TABLES | MD_FLAG_STRIKETHROUGH | MD_FLAG_TASKLISTS
    | MD_FLAG_PERMISSIVEAUTOLINKS | MD_FLAG_NOINDENTEDCODEBLOCKS | MD_FLAG_NOHTML;

void appendUTF16(std::u16string &output, char32_t codePoint) {
    if (codePoint < 0x10000) {
        output.push_back(static_cast<char16_t>(codePoint));
    } else {
        codePoint -= 0x10000;
        output.push_back(static_cast<char16_t>(0xD800 + (codePoint >> 10)));
        output.push_back(static_cast<char16_t>(0xDC00 + (codePoint & 0x3FF)));
    }
}

std::u16string decodeUTF8(const char *bytes, size_t size) {
    std::u16string output;
    size_t index = 0;
    while (index < size) {
        auto lead = static_cast<unsigned char>(bytes[index]);
        size_t length = lead < 0x80 ? 1 : lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 0;
        if (length == 0 || index + length > size) {
            output.push_back(0xFFFD);
            index++;
            continue;
        }
        char32_t codePoint = length == 1 ? lead : lead & (0xFF >> (length + 1));
        for (size_t offset = 1; offset < length; offset++) {
            codePoint = (codePoint << 6) | (static_cast<unsigned char>(bytes[index + offset]) & 0x3F);
        }
        appendUTF16(output, codePoint);
        index += length;
    }
    return output;
}

/// The UTF-8 copy of the source that md4c parses, with the UTF-16 offset of every byte.
class UTF8Source {
public:
    explicit UTF8Source(std::u16string_view text) {
        bytes_.reserve(text.size() * 3);
        offsets_.reserve(text.size() * 3 + 1);
        for (size_t index = 0; index < text.size();) {
            char32_t codePoint = text[index];
            size_t units = 1;
            if (isHighSurrogate(text[index]) && index + 1 < text.size() && isLowSurrogate(text[index + 1])) {
                codePoint = codePointAt(text, index);
                units = 2;
            } else if (isHighSurrogate(text[index]) || isLowSurrogate(text[index])) {
                codePoint = 0xFFFD;
            }
            append(codePoint, static_cast<Offset>(index));
            index += units;
        }
        offsets_.push_back(static_cast<Offset>(text.size()));
    }

    const char *data() const { return bytes_.data(); }
    MD_SIZE size() const { return static_cast<MD_SIZE>(bytes_.size()); }

    std::optional<Range> range(const MD_CHAR *text, MD_SIZE size) const {
        if (text < bytes_.data() || text + size > bytes_.data() + bytes_.size()) {
            return std::nullopt;
        }
        size_t start = static_cast<size_t>(text - bytes_.data());
        return Range{offsets_[start], offsets_[start + size] - offsets_[start]};
    }

    Offset offset(MD_OFFSET byte) const {
        return offsets_[std::min<size_t>(byte, bytes_.size())];
    }

private:
    void append(char32_t codePoint, Offset offset) {
        auto push = [&](uint32_t byte) {
            bytes_.push_back(static_cast<char>(byte));
            offsets_.push_back(offset);
        };
        if (codePoint < 0x80) {
            push(codePoint);
        } else if (codePoint < 0x800) {
            push(0xC0 | (codePoint >> 6));
            push(0x80 | (codePoint & 0x3F));
        } else if (codePoint < 0x10000) {
            push(0xE0 | (codePoint >> 12));
            push(0x80 | ((codePoint >> 6) & 0x3F));
            push(0x80 | (codePoint & 0x3F));
        } else {
            push(0xF0 | (codePoint >> 18));
            push(0x80 | ((codePoint >> 12) & 0x3F));
            push(0x80 | ((codePoint >> 6) & 0x3F));
            push(0x80 | (codePoint & 0x3F));
        }
    }

    std::string bytes_;
    std::vector<Offset> offsets_;
};

enum class EventType : uint8_t {
    EnterBlock,
    LeaveBlock,
    EnterSpan,
    LeaveSpan,
    Text,
};

struct Event {
    EventType type;
    int code = 0;
    Range range;
    /// Heading level, ordered list start, or table column count.
    unsigned number = 0;
    /// Whether a list item is a task, or a link is an autolink.
    bool flag = false;
    bool checked = false;
    Offset taskMark = 0;
    /// Link destination or code block language.
    std::u16string attribute;
};

struct Recorder {
    const UTF8Source &source;
    std::vector<Event> events;
};

std::u16string decode(const MD_ATTRIBUTE &attribute) {
    return decodeUTF8(attribute.text, attribute.size);
}

int enterBlock(MD_BLOCKTYPE type, void *detail, void *userdata) {
    auto &recorder = *static_cast<Recorder *>(userdata);
    Event event{EventType::EnterBlock, type};
    switch (type) {
    case MD_BLOCK_H:
        event.number = static_cast<MD_BLOCK_H_DETAIL *>(detail)->level;
        break;
    case MD_BLOCK_OL:
        event.number = static_cast<MD_BLOCK_OL_DETAIL *>(detail)->start;
        break;
    case MD_BLOCK_LI: {
        auto item = static_cast<MD_BLOCK_LI_DETAIL *>(detail);
        event.flag = item->is_task;
        if (item->is_task) {
            event.checked = item->task_mark != ' ';
            event.taskMark = recorder.source.offset(item->task_mark_offset);
        }
        break;
    }
    case MD_BLOCK_CODE:
        event.attribute = decode(static_cast<MD_BLOCK_CODE_DETAIL *>(detail)->lang);
        break;
    case MD_BLOCK_TABLE:
        event.number = static_cast<MD_BLOCK_TABLE_DETAIL *>(detail)->col_count;
        break;
    default:
        break;
    }
    recorder.events.push_back(std::move(event));
    return 0;
}

int leaveBlock(MD_BLOCKTYPE type, void *, void *userdata) {
    static_cast<Recorder *>(userdata)->events.push_back({EventType::LeaveBlock, type});
    return 0;
}

int enterSpan(MD_SPANTYPE type, void *detail, void *userdata) {
    auto &recorder = *static_cast<Recorder *>(userdata);
    Event event{EventType::EnterSpan, type};
    if (type == MD_SPAN_A) {
        auto link = static_cast<MD_SPAN_A_DETAIL *>(detail);
        event.flag = link->is_autolink;
        event.attribute = decode(link->href);
    }
    recorder.events.push_back(std::move(event));
    return 0;
}

int leaveSpan(MD_SPANTYPE type, void *, void *userdata) {
    static_cast<Recorder *>(userdata)->events.push_back({EventType::LeaveSpan, type});
    return 0;
}

int text(MD_TEXTTYPE, const MD_CHAR *text, MD_SIZE size, void *userdata) {
    auto &recorder = *static_cast<Recorder *>(userdata);
    // Line breaks and expanded indentation come from static strings rather than the source.
    if (auto range = recorder.source.range(text, size)) {
        Event event{EventType::Text};
        event.range = *range;
        recorder.events.push_back(std::move(event));
    }
    return 0;
}

size_t skipWhitespace(std::u16string_view text, size_t index) {
    while (index < text.size() && isWhitespace(text[index])) {
        index++;
    }
    return index;
}

bool isBlank(std::u16string_view text) {
    return skipWhitespace(text, 0) == text.size();
}

/// Skips indentation and quote markers, which may precede any block's syntax.
size_t containerPrefixEnd(std::u16string_view line) {
    size_t index = skipWhitespace(line, 0);
    while (index < line.size() && line[index] == u'>') {
        index = skipWhitespace(line, index + 1);
    }
    return index;
}

bool consistsOf(std::u16string_view text, std::u16string_view characters) {
    return !text.empty() && text.find_first_not_of(characters) == std::u16string_view::npos;
}

/// The end of a list marker such as `-` or `12.` at `index`, if there is one.
std::optional<size_t> listMarkerEnd(std::u16string_view line, size_t index) {
    size_t end = index;
    if (end < line.size() && (line[end] == u'-' || line[end] == u'+' || line[end] == u'*')) {
        end++;
    } else {
        while (end < line.size() && isASCIIDigit(line[end])) {
            end++;
        }
        if (end == index || end >= line.size() || (line[end] != u'.' && line[end] != u')')) {
            return std::nullopt;
        }
        end++;
    }
    if (end < line.size() && !isWhitespace(line[end])) {
        return std::nullopt;
    }
    return end;
}

bool isFenceLine(std::u16string_view line) {
    std::u16string_view rest = line.substr(containerPrefixEnd(line));
    if (auto end = listMarkerEnd(rest, 0)) {
        rest = rest.substr(skipWhitespace(rest, *end));
    }
    return rest.starts_with(u"```") || rest.starts_with(u"~~~");
}

bool isRuleLine(std::u16string_view line) {
    std::u16string_view rest = line.substr(containerPrefixEnd(line));
    std::u16string trimmed;
    for (char16_t unit : rest) {
        if (!isWhitespace(unit)) {
            trimmed.push_back(unit);
        }
    }
    return trimmed.size() >= 3 && (consistsOf(trimmed, u"-") || consistsOf(trimmed, u"*") || consistsOf(trimmed, u"_"));
}

bool isHeadingLine(std::u16string_view line) {
    std::u16string_view rest = line.substr(containerPrefixEnd(line));
    size_t hashes = 0;
    while (hashes < rest.size() && rest[hashes] == u'#') {
        hashes++;
    }
    return hashes >= 1 && hashes <= 6 && (hashes == rest.size() || isWhitespace(rest[hashes]));
}

bool isSetextUnderline(std::u16string_view line) {
    std::u16string_view rest = line.substr(containerPrefixEnd(line));
    size_t end = rest.size();
    while (end > 0 && isWhitespace(rest[end - 1])) {
        end--;
    }
    rest = rest.substr(0, end);
    return consistsOf(rest, u"=") || consistsOf(rest, u"-");
}

bool isTableDelimiterRow(std::u16string_view line) {
    std::u16string_view rest = line.substr(containerPrefixEnd(line));
    return rest.find(u'-') != std::u16string_view::npos && consistsOf(rest, u"|:- \t");
}

bool isQuoteOnly(std::u16string_view line) {
    return line.find(u'>') != std::u16string_view::npos && containerPrefixEnd(line) == line.size();
}

struct BlockFrame {
    int type = 0;
    KindSet kinds = 0;
    size_t event = 0;
    std::optional<size_t> firstLine;
    size_t lastLine = 0;
    /// The ordinal the next item of an ordered list takes.
    uint64_t nextOrdinal = 0;
    uint64_t ordinal = 0;
    bool ordered = false;
    std::optional<Range> marker;
    bool hasClosingFence = false;
};

struct SpanFrame {
    int type = 0;
    KindSet kinds = 0;
    /// Index into `Parse::spans`, or -1 for a span without text whose position is unknown.
    int32_t span = -1;
    Offset openerEnd = 0;
    Offset delimiterLength = 0;
    bool isAngleAutolink = false;
    size_t event = 0;
};

KindSet spanKind(int type) {
    switch (type) {
    case MD_SPAN_EM:
        return Emphasis;
    case MD_SPAN_STRONG:
        return Strong;
    case MD_SPAN_DEL:
        return Strikethrough;
    case MD_SPAN_CODE:
        return CodeSpan;
    case MD_SPAN_A:
        return Link;
    case MD_SPAN_IMG:
        return Image;
    default:
        return 0;
    }
}

class Builder {
public:
    Builder(const Document &document, std::vector<Event> events)
        : document_(document), lines_(document.lines()), text_(document.text()), events_(std::move(events)) {
        size_t length = text_.size();
        result_.kinds.assign(length, 0);
        result_.depths.assign(length, 0);
        result_.markers.assign(length, NotMarker);
        result_.lines.resize(lines_.size());
        lineKinds_.assign(lines_.size(), 0);
        lineDepths_.assign(lines_.size(), 0);
        lineIsStyled_.assign(lines_.size(), false);
    }

    Parse run() {
        Offset cursor = 0;
        size_t gapStart = 0;
        for (size_t index = 0; index < events_.size(); index++) {
            const Event &event = events_[index];
            if (event.type != EventType::Text || event.range.location < cursor) {
                continue;
            }
            processGap(cursor, event.range.location, gapStart, index, true);
            applyText(event.range);
            cursor = event.range.end();
            previousTextLine_ = document_.lineIndex(cursor - 1);
            gapStart = index + 1;
        }
        processGap(cursor, document_.length(), gapStart, events_.size(), false);

        for (size_t index = 0; index < lines_.size(); index++) {
            for (Offset offset = lines_[index].contentEnd; offset < lines_[index].end; offset++) {
                result_.kinds[offset] = lineKinds_[index];
                result_.depths[offset] = lineDepths_[index];
            }
        }
        keepEmojiSequencesVisible();
        std::stable_sort(result_.elements.begin(), result_.elements.end(), [](const Element &a, const Element &b) {
            if (a.range.location != b.range.location) {
                return a.range.location < b.range.location;
            }
            return a.range.length > b.range.length;
        });
        return std::move(result_);
    }

private:
    KindSet blockKinds() const {
        KindSet kinds = 0;
        bool hasItem = false;
        for (auto frame = blocks_.rbegin(); frame != blocks_.rend(); ++frame) {
            if (frame->type == MD_BLOCK_LI) {
                if (hasItem) {
                    continue;
                }
                hasItem = true;
            }
            kinds |= frame->kinds;
        }
        return kinds;
    }

    KindSet spanKinds() const {
        KindSet kinds = 0;
        for (const auto &frame : spans_) {
            kinds |= frame.kinds;
        }
        return kinds;
    }

    size_t count(int type) const {
        return static_cast<size_t>(std::count_if(blocks_.begin(), blocks_.end(), [type](const BlockFrame &frame) {
            return frame.type == type;
        }));
    }

    /// The nesting level of the innermost list item, or else the number of enclosing quotes.
    uint8_t depth() const {
        size_t items = count(MD_BLOCK_LI);
        return static_cast<uint8_t>(std::min<size_t>(items > 0 ? items - 1 : count(MD_BLOCK_QUOTE), 255));
    }

    BlockFrame *innermost(int type) {
        for (auto frame = blocks_.rbegin(); frame != blocks_.rend(); ++frame) {
            if (frame->type == type) {
                return &*frame;
            }
        }
        return nullptr;
    }

    BlockKind blockKind(size_t line) const {
        for (auto frame = blocks_.rbegin(); frame != blocks_.rend(); ++frame) {
            switch (frame->type) {
            case MD_BLOCK_CODE:
                return BlockKind::Code;
            case MD_BLOCK_TABLE:
                return BlockKind::Table;
            case MD_BLOCK_HR:
                return BlockKind::Rule;
            case MD_BLOCK_H:
                return BlockKind::Heading;
            case MD_BLOCK_LI:
                if (!frame->firstLine || *frame->firstLine == line) {
                    return events_[frame->event].flag ? BlockKind::Task : BlockKind::ListItem;
                }
                break;
            case MD_BLOCK_QUOTE:
                return BlockKind::Quote;
            default:
                break;
            }
        }
        return BlockKind::Paragraph;
    }

    /// Records that `line` holds content of the open blocks.
    void touch(size_t line) {
        if (!lineIsStyled_[line]) {
            lineIsStyled_[line] = true;
            lineKinds_[line] = blockKinds();
            lineDepths_[line] = depth();
            result_.lines[line].block = blockKind(line);
        }
        for (auto &frame : blocks_) {
            if (!frame.firstLine) {
                frame.firstLine = line;
            }
            frame.lastLine = std::max(frame.lastLine, line);
        }
    }

    void mark(Offset start, Offset end, KindSet kinds, uint8_t depth, int32_t owner) {
        for (Offset offset = start; offset < end; offset++) {
            if (isLineBreak(text_[offset])) {
                continue;
            }
            result_.kinds[offset] = kinds | Marker;
            result_.depths[offset] = depth;
            result_.markers[offset] = owner;
        }
    }

    int32_t blockMarkerOwner() const {
        return count(MD_BLOCK_TABLE) > 0 ? VisibleMarker : BlockMarker;
    }

    void applyText(Range range) {
        KindSet kinds = blockKinds() | spanKinds();
        uint8_t level = depth();
        for (Offset offset = range.location; offset < range.end(); offset++) {
            if (!isLineBreak(text_[offset])) {
                result_.kinds[offset] = kinds;
                result_.depths[offset] = level;
            }
        }
        if (range.length == 0) {
            return;
        }
        size_t last = document_.lineIndex(range.end() - 1);
        for (size_t line = document_.lineIndex(range.location); line <= last; line++) {
            touch(line);
        }
    }

    /// Marks a whole line without text as block syntax, such as a code fence or a rule.
    void markLine(size_t line) {
        touch(line);
        const Line &bounds = lines_[line];
        mark(bounds.start, bounds.contentEnd, blockKinds(), depth(), blockMarkerOwner());
        result_.lines[line].prefixLength = bounds.contentEnd - bounds.start;
    }

    void processGap(Offset start, Offset end, size_t firstEvent, size_t lastEvent, bool isFollowedByText) {
        Offset position = start;
        size_t index = firstEvent;
        while (index < lastEvent && events_[index].type == EventType::LeaveSpan && !spans_.empty()) {
            position = closeSpan(position, end);
            index++;
        }

        size_t firstOpener = lastEvent;
        while (firstOpener > index && events_[firstOpener - 1].type == EventType::EnterSpan) {
            firstOpener--;
        }
        std::vector<Offset> openerLengths(lastEvent - firstOpener);
        Offset openersStart = end;
        for (size_t opener = lastEvent; opener > firstOpener; opener--) {
            Offset length = openerLength(events_[opener - 1], openersStart, position);
            openerLengths[opener - 1 - firstOpener] = length;
            openersStart -= length;
        }

        std::optional<size_t> previousLine = previousTextLine_;
        std::optional<size_t> nextLine = isFollowedByText ? std::optional(document_.lineIndex(end)) : std::nullopt;
        bareLines_.clear();
        nextBareLine_ = 0;
        if (openersStart > position || (!previousLine && !nextLine)) {
            size_t last = document_.lineIndex(openersStart);
            for (size_t line = document_.lineIndex(position); line <= last; line++) {
                if (line != previousLine && line != nextLine) {
                    bareLines_.push_back(line);
                }
            }
        }

        for (; index < firstOpener; index++) {
            applyMiddleEvent(index);
        }

        for (size_t line : bareLines_) {
            if (lineIsStyled_[line]) {
                continue;
            }
            std::u16string_view content = document_.content(lines_[line]);
            if (isBlank(content)) {
                if (firstEvent == lastEvent && !blocks_.empty()) {
                    touch(line);
                }
            } else if (isQuoteOnly(content) && count(MD_BLOCK_QUOTE) > 0) {
                markLine(line);
            }
        }

        if (nextLine) {
            const Line &line = lines_[*nextLine];
            if (previousLine == nextLine) {
                if (openersStart > position) {
                    markInlineSyntax(position, openersStart);
                }
            } else {
                // An opener can sit on an earlier line, as in a link whose text starts on the next line.
                Offset prefixStart = std::max(position, line.start);
                Offset prefixEnd = std::max(prefixStart, openersStart);
                touch(*nextLine);
                mark(prefixStart, prefixEnd, blockKinds(), depth(), blockMarkerOwner());
                result_.lines[*nextLine].prefixLength = prefixEnd - line.start;
                assignListMarkers(prefixStart, prefixEnd);
            }
        }
        if (previousLine && previousLine != nextLine) {
            Offset trailingEnd = std::min(openersStart, lines_[*previousLine].contentEnd);
            KindSet kinds = lineKinds_[*previousLine];
            mark(position, std::max(position, trailingEnd), kinds, lineDepths_[*previousLine],
                 kinds & Table ? VisibleMarker : BlockMarker);
        }

        Offset openerStart = openersStart;
        for (size_t opener = firstOpener; opener < lastEvent; opener++) {
            Offset length = openerLengths[opener - firstOpener];
            openSpan(opener, openerStart, length);
            openerStart += length;
        }
    }

    /// Marks syntax between two runs of text on the same line, such as a backslash escape.
    void markInlineSyntax(Offset start, Offset end) {
        KindSet kinds = blockKinds() | spanKinds();
        if (count(MD_BLOCK_TABLE) > 0) {
            mark(start, end, kinds, depth(), VisibleMarker);
            return;
        }
        result_.spans.push_back({{start, end - start}, {end, 0}, 0});
        mark(start, end, kinds, depth(), static_cast<int32_t>(result_.spans.size() - 1));
    }

    /// Gives list items that started in this gap the markers found in their line's prefix.
    void assignListMarkers(Offset start, Offset end) {
        std::u16string_view prefix = document_.substring({start, end - start});
        size_t index = 0;
        for (auto &frame : blocks_) {
            if (frame.type != MD_BLOCK_LI || frame.marker) {
                continue;
            }
            while (index < prefix.size()) {
                if (auto markerEnd = listMarkerEnd(prefix, index)) {
                    frame.marker = Range{start + static_cast<Offset>(index), static_cast<Offset>(*markerEnd - index)};
                    index = *markerEnd;
                    break;
                }
                index++;
            }
        }
    }

    /// The next line without text in the current gap that isn't blank.
    std::optional<size_t> peekBareLine() {
        while (nextBareLine_ < bareLines_.size()) {
            size_t line = bareLines_[nextBareLine_];
            if (!isBlank(document_.content(lines_[line])) && !lineIsStyled_[line]) {
                return line;
            }
            nextBareLine_++;
        }
        return std::nullopt;
    }

    /// Claims the next line without text if it matches `pattern`, marking it as block syntax.
    std::optional<size_t> claimBareLine(bool (*pattern)(std::u16string_view)) {
        auto line = peekBareLine();
        if (!line || !pattern(document_.content(lines_[*line]))) {
            return std::nullopt;
        }
        nextBareLine_++;
        markLine(*line);
        return line;
    }

    void applyMiddleEvent(size_t index) {
        const Event &event = events_[index];
        switch (event.type) {
        case EventType::EnterBlock:
            enterBlock(index);
            break;
        case EventType::LeaveBlock:
            leaveBlock();
            break;
        case EventType::EnterSpan:
            spans_.push_back({event.code, spanKind(event.code), -1, 0, 0, false, index});
            break;
        case EventType::LeaveSpan:
            if (!spans_.empty()) {
                spans_.pop_back();
            }
            break;
        case EventType::Text:
            break;
        }
    }

    void enterBlock(size_t index) {
        const Event &event = events_[index];
        BlockFrame frame;
        frame.type = event.code;
        frame.event = index;
        switch (event.code) {
        case MD_BLOCK_H:
            frame.kinds = Heading1 << (std::clamp(event.number, 1u, 6u) - 1);
            break;
        case MD_BLOCK_QUOTE:
            frame.kinds = Quote;
            break;
        case MD_BLOCK_OL:
            frame.nextOrdinal = event.number;
            break;
        case MD_BLOCK_LI:
            frame.kinds = event.flag ? (TaskItem | (event.checked ? TaskChecked : 0)) : ListItem;
            if (event.flag && event.taskMark > 0) {
                frame.marker = Range{event.taskMark - 1, 3};
            }
            if (!blocks_.empty() && blocks_.back().type == MD_BLOCK_OL) {
                frame.ordered = true;
                frame.ordinal = blocks_.back().nextOrdinal++;
            }
            break;
        case MD_BLOCK_HR:
            frame.kinds = Rule;
            break;
        case MD_BLOCK_CODE:
            frame.kinds = CodeBlock;
            break;
        case MD_BLOCK_TABLE:
            frame.kinds = Table;
            break;
        case MD_BLOCK_THEAD:
            frame.kinds = TableHeader;
            break;
        default:
            break;
        }
        blocks_.push_back(frame);

        switch (event.code) {
        case MD_BLOCK_CODE:
            if (auto line = claimBareLine(isFenceLine)) {
                blocks_.back().marker = lines_[*line].contentRange();
            }
            break;
        case MD_BLOCK_HR:
            claimBareLine(isRuleLine);
            break;
        case MD_BLOCK_H:
            claimBareLine(isHeadingLine);
            break;
        case MD_BLOCK_QUOTE:
            claimBareLine(isQuoteOnly);
            break;
        case MD_BLOCK_LI:
            claimListItemLine();
            break;
        default:
            break;
        }
    }

    /// An empty list item, or one whose first line holds another block such as a code fence.
    void claimListItemLine() {
        auto line = peekBareLine();
        if (!line) {
            return;
        }
        std::u16string_view content = document_.content(lines_[*line]);
        size_t markerStart = containerPrefixEnd(content);
        auto markerEnd = listMarkerEnd(content, markerStart);
        if (!markerEnd) {
            return;
        }
        BlockFrame &frame = blocks_.back();
        if (!frame.marker) {
            frame.marker = Range{
                lines_[*line].start + static_cast<Offset>(markerStart),
                static_cast<Offset>(*markerEnd - markerStart),
            };
        }
        touch(*line);
        size_t rest = skipWhitespace(content, *markerEnd);
        if (std::u16string_view(content).substr(rest).starts_with(u"[") && rest + 3 <= content.size()
            && content[rest + 2] == u']') {
            rest = skipWhitespace(content, rest + 3);
        }
        if (rest == content.size()) {
            nextBareLine_++;
            markLine(*line);
        }
    }

    void leaveBlock() {
        if (blocks_.empty()) {
            return;
        }
        BlockFrame &frame = blocks_.back();
        switch (frame.type) {
        case MD_BLOCK_CODE:
            if (auto line = claimBareLine(isFenceLine)) {
                frame.hasClosingFence = true;
                frame.lastLine = *line;
            }
            if (frame.firstLine) {
                for (size_t line = *frame.firstLine + 1; line < frame.lastLine; line++) {
                    if (!lineIsStyled_[line]) {
                        touch(line);
                    }
                }
            }
            break;
        case MD_BLOCK_H:
            claimBareLine(isSetextUnderline);
            break;
        case MD_BLOCK_THEAD:
            if (auto line = claimBareLine(isTableDelimiterRow)) {
                if (BlockFrame *table = innermost(MD_BLOCK_TABLE)) {
                    table->marker = lines_[*line].contentRange();
                }
            }
            break;
        default:
            break;
        }
        addElement(blocks_.back());
        blocks_.pop_back();
    }

    void addElement(const BlockFrame &frame) {
        if (!frame.firstLine) {
            return;
        }
        const Line &first = lines_[*frame.firstLine];
        const Line &last = lines_[frame.lastLine];
        Element element;
        element.range = {first.start, last.contentEnd - first.start};
        element.contentRange = element.range;
        element.markerRange = frame.marker.value_or(Range{first.start, 0});
        switch (frame.type) {
        case MD_BLOCK_LI: {
            const Event &event = events_[frame.event];
            element.kind = event.flag ? ElementKind::Task : ElementKind::ListItem;
            Offset contentStart = std::min(first.start + result_.lines[*frame.firstLine].prefixLength, element.range.end());
            element.contentRange = {contentStart, element.range.end() - contentStart};
            element.depth = static_cast<uint32_t>(count(MD_BLOCK_LI) - 1);
            element.ordered = frame.ordered;
            element.ordinal = frame.ordinal;
            element.checked = event.checked;
            break;
        }
        case MD_BLOCK_QUOTE: {
            element.kind = ElementKind::Quote;
            size_t marker = document_.content(first).find(u'>');
            if (marker != std::u16string_view::npos) {
                element.markerRange = {first.start + static_cast<Offset>(marker), 1};
            }
            element.depth = static_cast<uint32_t>(count(MD_BLOCK_QUOTE));
            break;
        }
        case MD_BLOCK_CODE: {
            element.kind = ElementKind::CodeBlock;
            element.language = events_[frame.event].attribute;
            size_t contentFirst = *frame.firstLine + (frame.marker ? 1 : 0);
            size_t contentLast = frame.hasClosingFence ? frame.lastLine - 1 : frame.lastLine;
            if (contentFirst <= contentLast && contentFirst < lines_.size()) {
                Offset start = lines_[contentFirst].start;
                element.contentRange = {start, lines_[contentLast].contentEnd - start};
            } else {
                Offset start = contentFirst < lines_.size() ? lines_[contentFirst].start : element.range.end();
                element.contentRange = {std::min(start, element.range.end()), 0};
            }
            break;
        }
        case MD_BLOCK_HR:
            element.kind = ElementKind::Rule;
            element.markerRange = element.range;
            element.contentRange = {element.range.end(), 0};
            break;
        case MD_BLOCK_TABLE:
            element.kind = ElementKind::Table;
            element.columnCount = events_[frame.event].number;
            break;
        default:
            return;
        }
        result_.elements.push_back(std::move(element));
    }

    Offset openerLength(const Event &event, Offset end, Offset start) const {
        auto before = [&](Offset distance) -> char16_t {
            return end >= start + distance ? text_[end - distance] : 0;
        };
        switch (event.code) {
        case MD_SPAN_EM:
            return before(1) == u'*' || before(1) == u'_' ? 1 : 0;
        case MD_SPAN_STRONG:
        case MD_SPAN_DEL: {
            char16_t delimiter = before(1);
            bool matches = event.code == MD_SPAN_DEL ? delimiter == u'~' : delimiter == u'*' || delimiter == u'_';
            if (!matches) {
                return 0;
            }
            return before(2) == delimiter ? 2 : 1;
        }
        case MD_SPAN_CODE: {
            Offset length = before(1) == u' ' && before(2) == u'`' ? 1 : 0;
            while (before(length + 1) == u'`') {
                length++;
            }
            return length;
        }
        case MD_SPAN_A:
            if (event.flag) {
                return before(1) == u'<' ? 1 : 0;
            }
            return before(1) == u'[' ? 1 : 0;
        case MD_SPAN_IMG:
            return before(2) == u'!' && before(1) == u'[' ? 2 : 0;
        default:
            return 0;
        }
    }

    void openSpan(size_t index, Offset start, Offset length) {
        const Event &event = events_[index];
        SpanFrame frame{event.code, spanKind(event.code), -1, start + length, 0, false, index};
        switch (event.code) {
        case MD_SPAN_EM:
        case MD_SPAN_STRONG:
        case MD_SPAN_DEL:
            frame.delimiterLength = event.code == MD_SPAN_EM ? 1 : event.code == MD_SPAN_STRONG ? 2 : length;
            break;
        case MD_SPAN_CODE:
            frame.delimiterLength = length > 0 && text_[start + length - 1] == u' ' ? length - 1 : length;
            break;
        case MD_SPAN_A:
            frame.isAngleAutolink = event.flag && length == 1;
            break;
        default:
            break;
        }
        result_.spans.push_back({{start, 0}, {start + length, 0}, frame.kinds});
        frame.span = static_cast<int32_t>(result_.spans.size() - 1);
        spans_.push_back(frame);
        int32_t owner = event.code == MD_SPAN_IMG ? VisibleMarker : frame.span;
        mark(start, start + length, blockKinds() | spanKinds(), depth(), owner);
    }

    Offset closerLength(const SpanFrame &frame, Offset start, Offset end) const {
        auto at = [&](Offset offset) -> char16_t {
            return offset < end ? text_[offset] : 0;
        };
        switch (frame.type) {
        case MD_SPAN_EM:
        case MD_SPAN_STRONG:
        case MD_SPAN_DEL: {
            char16_t delimiter = at(start);
            bool matches = frame.type == MD_SPAN_DEL ? delimiter == u'~' : delimiter == u'*' || delimiter == u'_';
            Offset length = 0;
            while (matches && length < frame.delimiterLength && at(start + length) == delimiter) {
                length++;
            }
            return length;
        }
        case MD_SPAN_CODE: {
            Offset length = at(start) == u' ' && at(start + 1) == u'`' ? 1 : 0;
            Offset backticks = 0;
            while (backticks < frame.delimiterLength && at(start + length) == u'`') {
                length++;
                backticks++;
            }
            return length;
        }
        case MD_SPAN_A:
        case MD_SPAN_IMG: {
            if (events_[frame.event].flag) {
                return frame.isAngleAutolink && at(start) == u'>' ? 1 : 0;
            }
            if (at(start) != u']') {
                return 0;
            }
            Offset offset = start + 1;
            if (at(offset) == u'(') {
                int nesting = 0;
                while (offset < end) {
                    char16_t unit = text_[offset];
                    if (unit == u'\\') {
                        offset += 2;
                        continue;
                    }
                    offset++;
                    if (unit == u'(') {
                        nesting++;
                    } else if (unit == u')' && --nesting == 0) {
                        break;
                    }
                }
            } else if (at(offset) == u'[') {
                while (offset < end && text_[offset] != u']') {
                    offset++;
                }
                offset++;
            }
            return std::min(offset, end) - start;
        }
        default:
            return 0;
        }
    }

    /// The destination inside a link's closing syntax such as `](https://example.com "Title")`.
    std::optional<Range> destinationRange(Offset start, Offset end) const {
        if (end - start < 3 || text_[start + 1] != u'(') {
            return std::nullopt;
        }
        Offset location = static_cast<Offset>(skipWhitespace(std::u16string_view(text_).substr(0, end - 1), start + 2));
        Offset finish = location;
        if (location < end - 1 && text_[location] == u'<') {
            while (finish < end - 1 && text_[finish] != u'>') {
                finish++;
            }
            finish = std::min<Offset>(finish + 1, end - 1);
        } else {
            while (finish < end - 1 && !isWhitespace(text_[finish])) {
                finish++;
            }
        }
        return Range{location, finish - location};
    }

    Offset closeSpan(Offset start, Offset end) {
        SpanFrame frame = spans_.back();
        Offset length = closerLength(frame, start, end);
        KindSet kinds = blockKinds() | spanKinds();
        int32_t owner = frame.type == MD_SPAN_IMG ? VisibleMarker : frame.span;
        mark(start, start + length, kinds, depth(), owner);
        spans_.pop_back();
        if (frame.span < 0) {
            return start + length;
        }

        InlineSpan &span = result_.spans[frame.span];
        span.range.length = start + length - span.range.location;
        span.contentRange.length = start - span.contentRange.location;
        if (frame.type == MD_SPAN_A) {
            Element element;
            element.kind = ElementKind::Link;
            element.range = span.range;
            element.contentRange = span.contentRange;
            element.markerRange = {start + length, 0};
            element.url = events_[frame.event].attribute;
            if (auto destination = destinationRange(start, start + length)) {
                element.markerRange = *destination;
                for (Offset offset = destination->location; offset < destination->end(); offset++) {
                    result_.kinds[offset] |= LinkURL;
                }
            }
            result_.elements.push_back(std::move(element));
        }
        return start + length;
    }

    /// AppKit renders a whole emoji sequence such as `*️⃣` in the emoji font, so a marker
    /// character inside one can't be hidden through attributes alone.
    void keepEmojiSequencesVisible() {
        for (size_t index = 0; index < text_.size(); index++) {
            if (result_.markers[index] == NotMarker) {
                continue;
            }
            bool joinsNext = index + 1 < text_.size() && isEmojiJoiner(text_[index + 1]);
            bool joinsPrevious = index > 0 && text_[index - 1] == 0x200D;
            if (joinsNext || joinsPrevious) {
                result_.markers[index] = VisibleMarker;
            }
        }
    }

    const Document &document_;
    const std::vector<Line> &lines_;
    std::u16string_view text_;
    std::vector<Event> events_;
    Parse result_;
    std::vector<BlockFrame> blocks_;
    std::vector<SpanFrame> spans_;
    std::vector<KindSet> lineKinds_;
    std::vector<uint8_t> lineDepths_;
    std::vector<bool> lineIsStyled_;
    std::optional<size_t> previousTextLine_;
    std::vector<size_t> bareLines_;
    size_t nextBareLine_ = 0;
};

} // namespace

Parse parse(const Document &document) {
    UTF8Source source(document.text());
    Recorder recorder{source, {}};
    MD_PARSER parser{};
    parser.flags = parserFlags;
    parser.enter_block = enterBlock;
    parser.leave_block = leaveBlock;
    parser.enter_span = enterSpan;
    parser.leave_span = leaveSpan;
    parser.text = text;
    md_parse(source.data(), source.size(), &parser, &recorder);
    return Builder(document, std::move(recorder.events)).run();
}

} // namespace markdown
