//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

#pragma once

#include "Document.hpp"
#include "Parser.hpp"
#include "Types.hpp"

#include <vector>

namespace markdown {

/// Whether each code unit is concealed while `selection` is selected.
///
/// Block syntax shows on every line the selection touches. Inline delimiters show when their
/// element touches the selection, end points included, so the caret never sits next to a
/// hidden delimiter. In `RevealMode::Line` they show on every touched line as well.
std::vector<uint8_t> conceal(const Document &document, const Parse &parse, Range selection, RevealMode mode);

} // namespace markdown
