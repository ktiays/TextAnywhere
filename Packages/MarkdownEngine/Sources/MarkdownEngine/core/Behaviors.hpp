//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

#pragma once

#include "Document.hpp"
#include "Parser.hpp"
#include "Types.hpp"

#include <optional>

namespace markdown {

/// Continues a list, task list or quote on a new line, or ends it when the item is empty.
std::optional<EditPlan> planNewline(const Document &document, const Parse &parse, Range selection);

/// Indents or outdents the list items that the selection touches.
std::optional<EditPlan> planTab(const Document &document, const Parse &parse, Range selection, bool backward);

/// Removes a line's block syntax when the caret sits right after it.
std::optional<EditPlan> planBackspace(const Document &document, const Parse &parse, Range selection);

/// Checks or unchecks the task containing `offset`.
std::optional<EditPlan> planToggleTask(const Parse &parse, Offset offset);

/// Wraps the selection, or the word at the caret, in a format's delimiters, or unwraps the
/// element of that format that encloses the selection.
std::optional<EditPlan> planToggleFormat(const Document &document, const Parse &parse, InlineFormat format, Range selection);

} // namespace markdown
