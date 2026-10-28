# Third-party notices

## Material Icon Theme

The file icons in `Carrier.app` (`macos/Sources/CarrierCore/Resources/FileIcons`) are a subset of
[Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme), copied unchanged from the
npm package `material-icon-theme` 5.39.0. Copyright (c) 2025 Material Extensions, under the MIT licence:

```
The MIT License (MIT)
Copyright (c) 2025 Material Extensions

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

The same text ships inside the app, next to the icons. The pinned release, its integrity hash and how to refresh the
subset are in `macos/Sources/CarrierCore/Resources/FileIcons/SOURCE.txt`.

## LobeHub Icons

The provider marks in `Carrier.app` (`macos/Sources/CarrierCore/Resources/ProviderIcons`: Claude, Codex, Antigravity) are
copied unchanged from the npm package `@lobehub/icons-static-svg` 1.98.0 of
[LobeHub Icons](https://github.com/lobehub/lobe-icons). Copyright (c) 2023 LobeHub, under the MIT licence; the text
ships inside the app, next to the icons. The licence covers the artwork files, not the marks, which are trademarks of
Anthropic, OpenAI and Google. The pinned release and its integrity hash are in
`macos/Sources/CarrierCore/Resources/ProviderIcons/SOURCE.txt`.

## Claude Agent SDK

The Claude adapter of the chat host (`src/chat/claude.ts`) depends on the npm package
[`@anthropic-ai/claude-agent-sdk`](https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk), pinned to 0.3.311. It
is not open source and not covered by this repository's MIT licence. Its `package.json` declares the licence as
"SEE LICENSE IN README.md", and the `LICENSE.md` it ships says, in full:

```
© Anthropic PBC. All rights reserved. Use is subject to the Legal Agreements outlined here: https://code.claude.com/docs/en/legal-and-compliance.
```

Carrier does not copy or modify the package; it is installed from npm as a dependency. The package also lists the
platform builds of Claude Code (`@anthropic-ai/claude-agent-sdk-<os>-<cpu>`) as optional dependencies, under the same
terms; Carrier always points the SDK at the user's own `claude` binary and does not use them.
