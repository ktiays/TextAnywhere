//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

#import "MarkdownEngine.h"

#include "core/Engine.hpp"

#include <algorithm>
#include <memory>

#if !__has_feature(objc_arc)
#error "Engine.mm must be compiled with ARC."
#endif

static_assert(uint32_t(TAMarkdownKindHeading1) == uint32_t(markdown::Heading1) && uint32_t(TAMarkdownKindMarker) == uint32_t(markdown::Marker));
static_assert(TAMarkdownElementKindTable == static_cast<NSInteger>(markdown::ElementKind::Table));

static markdown::Range MakeRange(NSRange range) {
    markdown::Offset location = static_cast<markdown::Offset>(std::min<NSUInteger>(range.location, UINT32_MAX));
    markdown::Offset length = static_cast<markdown::Offset>(std::min<NSUInteger>(range.length, UINT32_MAX - location));
    return {location, length};
}

static NSRange MakeNSRange(markdown::Range range) {
    return NSMakeRange(range.location, range.length);
}

static std::u16string MakeString(NSString *string) {
    std::u16string result(string.length, u'\0');
    [string getCharacters:reinterpret_cast<unichar *>(result.data()) range:NSMakeRange(0, string.length)];
    return result;
}

static NSString *MakeNSString(const std::u16string &string) {
    return [NSString stringWithCharacters:reinterpret_cast<const unichar *>(string.data()) length:string.size()];
}

@implementation TAMarkdownOptions

- (id)copyWithZone:(NSZone *)zone {
    TAMarkdownOptions *copy = [[TAMarkdownOptions allocWithZone:zone] init];
    copy.revealMode = self.revealMode;
    return copy;
}

@end

@implementation TAMarkdownSegment

- (instancetype)initWithSegment:(const markdown::Segment &)segment {
    if ((self = [super init])) {
        _range = MakeNSRange(segment.range);
        _kinds = segment.kinds;
        _depth = segment.depth;
        _concealed = segment.concealed;
    }
    return self;
}

@end

@implementation TAMarkdownElement

- (instancetype)initWithElement:(const markdown::Element &)element {
    if ((self = [super init])) {
        _kind = static_cast<TAMarkdownElementKind>(element.kind);
        _range = MakeNSRange(element.range);
        _contentRange = MakeNSRange(element.contentRange);
        _markerRange = MakeNSRange(element.markerRange);
        _depth = element.depth;
        _ordered = element.ordered;
        _ordinal = element.ordinal;
        _checked = element.checked;
        _columnCount = element.columnCount;
        _url = element.kind == markdown::ElementKind::Link ? MakeNSString(element.url) : nil;
        _language = element.kind == markdown::ElementKind::CodeBlock ? MakeNSString(element.language) : nil;
    }
    return self;
}

@end

@implementation TAMarkdownPatch

- (instancetype)initWithPatch:(const markdown::Patch &)patch {
    if ((self = [super init])) {
        NSMutableArray<NSValue *> *ranges = [NSMutableArray arrayWithCapacity:patch.dirty.size()];
        for (const auto &range : patch.dirty) {
            [ranges addObject:[NSValue valueWithRange:MakeNSRange(range)]];
        }
        _dirtyRanges = [ranges copy];
    }
    return self;
}

@end

@implementation TAMarkdownEditPlan

- (instancetype)initWithPlan:(const markdown::EditPlan &)plan {
    if ((self = [super init])) {
        _replacementRange = MakeNSRange(plan.replace);
        _replacement = MakeNSString(plan.text);
        _selectionAfter = plan.selectionAfter ? MakeNSRange(*plan.selectionAfter) : NSMakeRange(NSNotFound, 0);
    }
    return self;
}

+ (nullable instancetype)planWithPlan:(const std::optional<markdown::EditPlan> &)plan {
    return plan ? [[TAMarkdownEditPlan alloc] initWithPlan:*plan] : nil;
}

@end

@implementation TAMarkdownEngine {
    std::unique_ptr<markdown::Engine> _engine;
}

- (instancetype)initWithText:(NSString *)text options:(TAMarkdownOptions *)options {
    if ((self = [super init])) {
        markdown::Options engineOptions;
        engineOptions.revealMode = options.revealMode == TAMarkdownRevealModeLine
            ? markdown::RevealMode::Line
            : markdown::RevealMode::Element;
        _engine = std::make_unique<markdown::Engine>(MakeString(text), engineOptions);
    }
    return self;
}

- (NSString *)text {
    return MakeNSString(_engine->text());
}

- (NSInteger)length {
    return _engine->length();
}

- (TAMarkdownPatch *)applyEditInRange:(NSRange)range replacement:(NSString *)replacement {
    return [[TAMarkdownPatch alloc] initWithPatch:_engine->applyEdit(MakeRange(range), MakeString(replacement))];
}

- (TAMarkdownPatch *)setSelectedRange:(NSRange)range {
    return [[TAMarkdownPatch alloc] initWithPatch:_engine->setSelection(MakeRange(range))];
}

- (NSArray<TAMarkdownSegment *> *)segmentsInRange:(NSRange)range {
    auto segments = _engine->segments(MakeRange(range));
    NSMutableArray<TAMarkdownSegment *> *result = [NSMutableArray arrayWithCapacity:segments.size()];
    for (const auto &segment : segments) {
        [result addObject:[[TAMarkdownSegment alloc] initWithSegment:segment]];
    }
    return result;
}

- (NSArray<TAMarkdownElement *> *)elementsInRange:(NSRange)range {
    auto elements = _engine->elements(MakeRange(range));
    NSMutableArray<TAMarkdownElement *> *result = [NSMutableArray arrayWithCapacity:elements.size()];
    for (const auto &element : elements) {
        [result addObject:[[TAMarkdownElement alloc] initWithElement:element]];
    }
    return result;
}

- (nullable TAMarkdownEditPlan *)planForNewlineAtRange:(NSRange)range {
    return [TAMarkdownEditPlan planWithPlan:_engine->planNewline(MakeRange(range))];
}

- (nullable TAMarkdownEditPlan *)planForTab:(BOOL)backward range:(NSRange)range {
    return [TAMarkdownEditPlan planWithPlan:_engine->planTab(MakeRange(range), backward)];
}

- (nullable TAMarkdownEditPlan *)planForBackspaceAtRange:(NSRange)range {
    return [TAMarkdownEditPlan planWithPlan:_engine->planBackspace(MakeRange(range))];
}

- (nullable TAMarkdownEditPlan *)planForTogglingTaskAtIndex:(NSInteger)index {
    auto offset = static_cast<markdown::Offset>(std::clamp<NSInteger>(index, 0, UINT32_MAX));
    return [TAMarkdownEditPlan planWithPlan:_engine->planToggleTask(offset)];
}

- (nullable TAMarkdownEditPlan *)planForToggling:(TAMarkdownInlineFormat)format range:(NSRange)range {
    markdown::InlineFormat inlineFormat;
    switch (format) {
    case TAMarkdownInlineFormatBold:
        inlineFormat = markdown::InlineFormat::Bold;
        break;
    case TAMarkdownInlineFormatItalic:
        inlineFormat = markdown::InlineFormat::Italic;
        break;
    case TAMarkdownInlineFormatStrikethrough:
        inlineFormat = markdown::InlineFormat::Strikethrough;
        break;
    case TAMarkdownInlineFormatCode:
        inlineFormat = markdown::InlineFormat::Code;
        break;
    default:
        return nil;
    }
    return [TAMarkdownEditPlan planWithPlan:_engine->planToggleFormat(inlineFormat, MakeRange(range))];
}

@end
