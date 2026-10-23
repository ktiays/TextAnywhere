//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Semantic kinds of a piece of Markdown source. Kinds combine: bold text in a heading is
/// `heading1` and `strong`, and its delimiters additionally carry `marker`.
typedef NS_OPTIONS(uint32_t, TAMarkdownKind) {
    TAMarkdownKindHeading1 = 1u << 0,
    TAMarkdownKindHeading2 = 1u << 1,
    TAMarkdownKindHeading3 = 1u << 2,
    TAMarkdownKindHeading4 = 1u << 3,
    TAMarkdownKindHeading5 = 1u << 4,
    TAMarkdownKindHeading6 = 1u << 5,
    TAMarkdownKindStrong = 1u << 6,
    TAMarkdownKindEmphasis = 1u << 7,
    TAMarkdownKindStrikethrough = 1u << 8,
    TAMarkdownKindCodeSpan = 1u << 9,
    TAMarkdownKindCodeBlock = 1u << 10,
    TAMarkdownKindLink = 1u << 11,
    TAMarkdownKindLinkURL = 1u << 12,
    TAMarkdownKindImage = 1u << 13,
    TAMarkdownKindQuote = 1u << 14,
    TAMarkdownKindListItem = 1u << 15,
    TAMarkdownKindTaskItem = 1u << 16,
    TAMarkdownKindTaskChecked = 1u << 17,
    TAMarkdownKindRule = 1u << 18,
    TAMarkdownKindTable = 1u << 19,
    TAMarkdownKindTableHeader = 1u << 20,
    TAMarkdownKindMarker = 1u << 21,
} NS_SWIFT_NAME(MarkdownKind);

typedef NS_ENUM(NSInteger, TAMarkdownElementKind) {
    TAMarkdownElementKindTask,
    TAMarkdownElementKindLink,
    TAMarkdownElementKindCodeBlock,
    TAMarkdownElementKindQuote,
    TAMarkdownElementKindRule,
    TAMarkdownElementKindListItem,
    TAMarkdownElementKindTable,
} NS_SWIFT_NAME(MarkdownElementKind);

typedef NS_ENUM(NSInteger, TAMarkdownInlineFormat) {
    TAMarkdownInlineFormatBold,
    TAMarkdownInlineFormatItalic,
    TAMarkdownInlineFormatStrikethrough,
    TAMarkdownInlineFormatCode,
} NS_SWIFT_NAME(MarkdownInlineFormat);

typedef NS_ENUM(NSInteger, TAMarkdownRevealMode) {
    /// Reveals the delimiters of each inline element that touches the selection.
    TAMarkdownRevealModeElement,
    /// Reveals every delimiter on the lines that the selection touches.
    TAMarkdownRevealModeLine,
} NS_SWIFT_NAME(MarkdownRevealMode);

NS_SWIFT_NAME(MarkdownOptions)
@interface TAMarkdownOptions : NSObject <NSCopying>

@property (nonatomic) TAMarkdownRevealMode revealMode;

@end

/// A maximal run of source with uniform styling. Segments returned for a range cover it
/// without gaps or overlaps.
NS_SWIFT_NAME(MarkdownSegment)
@interface TAMarkdownSegment : NSObject

@property (nonatomic, readonly) NSRange range;
@property (nonatomic, readonly) TAMarkdownKind kinds;
/// The nesting level of the enclosing list item counted from zero, or else the number of
/// enclosing quotes.
@property (nonatomic, readonly) NSInteger depth;
@property (nonatomic, readonly, getter=isConcealed) BOOL concealed;

- (instancetype)init NS_UNAVAILABLE;

@end

/// A block or inline construct for decorations and interactions.
NS_SWIFT_NAME(MarkdownElement)
@interface TAMarkdownElement : NSObject

@property (nonatomic, readonly) TAMarkdownElementKind kind;
@property (nonatomic, readonly) NSRange range;
@property (nonatomic, readonly) NSRange contentRange;
/// The syntax that identifies the element: a list marker, a task's `[ ]`, a link's
/// destination, a code block's opening fence or a table's delimiter row.
@property (nonatomic, readonly) NSRange markerRange;
@property (nonatomic, readonly) NSInteger depth;
@property (nonatomic, readonly, getter=isOrdered) BOOL ordered;
@property (nonatomic, readonly) uint64_t ordinal;
@property (nonatomic, readonly, getter=isChecked) BOOL checked;
@property (nonatomic, readonly) NSInteger columnCount;
@property (nonatomic, readonly, nullable, copy) NSString *url;
@property (nonatomic, readonly, nullable, copy) NSString *language;

- (instancetype)init NS_UNAVAILABLE;

@end

/// The ranges whose styling changed, in the coordinates after the change.
NS_SWIFT_NAME(MarkdownPatch)
@interface TAMarkdownPatch : NSObject

@property (nonatomic, readonly, copy) NSArray<NSValue *> *dirtyRanges;

- (instancetype)init NS_UNAVAILABLE;

@end

/// An edit for the host to perform through its undoable text system.
NS_SWIFT_NAME(MarkdownEditPlan)
@interface TAMarkdownEditPlan : NSObject

@property (nonatomic, readonly) NSRange replacementRange;
@property (nonatomic, readonly, copy) NSString *replacement;
/// The selection after the edit, or a range at `NSNotFound` when the selection should stay.
@property (nonatomic, readonly) NSRange selectionAfter;

- (instancetype)init NS_UNAVAILABLE;

@end

/// Styles a Markdown document whose source is held by the host. All offsets are UTF-16
/// code units, matching `NSString`.
NS_SWIFT_NAME(MarkdownEngine)
@interface TAMarkdownEngine : NSObject

@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly) NSInteger length;

- (instancetype)initWithText:(NSString *)text options:(TAMarkdownOptions *)options NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (TAMarkdownPatch *)applyEditInRange:(NSRange)range replacement:(NSString *)replacement;
/// Updates which syntax is revealed without reparsing.
- (TAMarkdownPatch *)setSelectedRange:(NSRange)range;

- (NSArray<TAMarkdownSegment *> *)segmentsInRange:(NSRange)range;
/// The elements that intersect `range`, or that contain it when it is empty.
- (NSArray<TAMarkdownElement *> *)elementsInRange:(NSRange)range;

/// Continues a list, task list or quote, or ends it when the item is empty.
- (nullable TAMarkdownEditPlan *)planForNewlineAtRange:(NSRange)range;
- (nullable TAMarkdownEditPlan *)planForTab:(BOOL)backward range:(NSRange)range NS_SWIFT_NAME(planForTab(backward:range:));
/// Removes a line's block syntax when the caret sits right after it.
- (nullable TAMarkdownEditPlan *)planForBackspaceAtRange:(NSRange)range;
- (nullable TAMarkdownEditPlan *)planForTogglingTaskAtIndex:(NSInteger)index;
- (nullable TAMarkdownEditPlan *)planForToggling:(TAMarkdownInlineFormat)format range:(NSRange)range NS_SWIFT_NAME(planForToggling(_:range:));

@end

NS_ASSUME_NONNULL_END
