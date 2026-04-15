## Limiting Changes to the Requested Task

Be sure to limit your changes to the things that I ask for. For example, if I ask you to add a button, don't make unrelated changes to other parts of the project.

## Coding Guidelines

- **Naming**: PascalCase for types, camelCase for properties/methods
- **Properties**: Use `@State private var` for SwiftUI state, `let` for constants
- **Structure**: Conform views to `View` protocol, define UI in `body` property
- **Formatting**: 4-space indentation, clear method separation
- **Imports**: Simple imports at top of file (SwiftUI, Foundation)
- **Types**: Leverage Swift's strong type system, avoid force unwrapping
- **Architecture**: Follow SwiftUI patterns with clear separation of concerns. Avoid using the Combine framework and instead prefer to use Swift's async and await versions of APIs instead.
- **Comments**: Add descriptive comments for complex logic or non-obvious code

## Commit Messages

- Use **imperative mood** (e.g., "Add audio preview controller", "Fix layout constraint on iPad").
- Do **not** use conventional commit prefixes (`feat:`, `fix:`, `chore:`, etc.).
- Write concise, professional English that summarizes the change.

## Comments

- **No comments** inside SwiftUI `View` `body` properties.
- **No redundant or obvious comments** anywhere in the codebase.
- Use `///` doc comments only on critical public APIs where the intent is not self-evident.
- All comments must be written in **English**.

## Code Hygiene

- No dead code or commented-out code left behind.
- Remove unused imports, variables, and functions.

## File Header

Every new code file must begin with a copyright header in the following format:

```
//
//  Created by <username> on <YYYY/M/D>.
//  Copyright (c) <YYYY> <username>. All rights reserved.
//
```

- `<username>`: the current macOS login username (e.g., `ktiays`).
- `<YYYY/M/D>`: the file creation date. Use the current date with no zero-padding on month and day (e.g., `2025/5/8`, not `2025/05/08`).
- `<YYYY>` in the copyright line: the same year as the creation date.
