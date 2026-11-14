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

The provider marks in `Carrier.app` (`macos/Sources/CarrierCore/Resources/ProviderIcons`: Claude, Codex, Antigravity, LM Studio, Ollama) are
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

## FluidAudio

The Carrier app (`macos/Package.swift`, the `Carrier` target only) links the Swift package
[FluidAudio](https://github.com/FluidInference/FluidAudio), pinned to 0.18.3, to run the Parakeet and Nemotron speech
models on Core ML for dictation. Copyright the FluidInference authors, under the Apache License 2.0 (its `LICENSE` names
no individual holder). Carrier does not modify it. The speech models are not part of the app: a person downloads them
from inside it.

FluidAudio is linked statically with works of its own that come with their own terms, and so the app carries FluidAudio's
`ThirdPartyLicenses` folder whole:

- `text-processing-rs` (`NemoTextProcessing`), a prebuilt library of FluidInference under the Apache License 2.0. It
  includes NVIDIA NeMo Text Processing (Apache-2.0), `rustfst` and `flate2` (MIT or Apache-2.0) and other permissive Rust
  crates; its notice is `NemoTextProcessing-LICENSE.md`.
- `fastcluster` (`FastClusterWrapper`), by Daniel Muellner and Google Inc., under the BSD licence, which asks that a binary
  distribution reproduce its copyright notice, conditions and disclaimer: `fastcluster-LICENSE.md`.
- The rest of that folder (VBx, the text frontends of the Kokoro and LuxTTS voices) is not used by dictation and comes with
  the library.

The texts of FluidAudio and of what it carries ship inside the app, in `Contents/Resources/Licenses/FluidAudio`.

## WhisperKit

The Carrier app (`macos/Package.swift`, the `Carrier` target only) links `WhisperKit`, a library of the Swift package
[argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift), pinned to 1.1.1, to run the Whisper speech models on
Core ML for dictation. Copyright (c) 2024 argmax, inc., under the MIT licence. Carrier does not modify it. The speech
models are not part of the app: a person downloads them from inside it. Its `LICENSE` and `NOTICES` ship inside the app, in
`Contents/Resources/Licenses/argmax-oss-swift`.

Part of the package is derived from the [swift-transformers](https://github.com/huggingface/swift-transformers) project
of Hugging Face (Copyright 2022 Hugging Face SAS) and is distributed under the Apache License 2.0, as modified by Argmax,
Inc. (<https://www.apache.org/licenses/LICENSE-2.0>); the package's own notice for it, with the full text of the Apache
License, is its [`NOTICES`](https://github.com/argmaxinc/argmax-oss-swift/blob/v1.1.1/NOTICES), the file that ships.

This file ships inside the app as well, in `Contents/Resources/Licenses/THIRD-PARTY-NOTICES.md`.

## Ghostty (`libghostty-spm` and `DisplayLink`)

The Carrier app (`macos/Package.swift`, the `Carrier` target only) links `GhosttyTerminal` from
[libghostty-spm](https://github.com/Lakr233/libghostty-spm) (pinned to 2.2.2026111302, Copyright (c) 2026 @Lakr233, MIT
License), which wraps [Ghostty](https://github.com/ghostty-org/ghostty)'s prebuilt `GhosttyKit.xcframework` (`libghostty`
and `xterm-ghostty` terminfo, MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors) and
[DisplayLink](https://github.com/Lakr233/DisplayLink) (pinned to 3.0.1, Copyright (c) 2024 Lakr Aream, MIT License).
Their bundled MIT licence texts ship inside the app in `Contents/Resources/Licenses/libghostty-spm/LICENSE` and
`Contents/Resources/Licenses/DisplayLink/LICENSE`, and Ghostty's upstream MIT notice is included below.

```text
MIT License

Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR OTHERWISE, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Speech models

None of these is part of the app or is redistributed by Carrier: a person downloads each from Hugging Face, from the
Dictation page of Settings, into `app/models` of the Carrier folder, and the page shows its licence with a link to its
card. Apple's own recognizer is managed by macOS and has no entry. Where a card and the app's list disagree, the list
follows the licence of the model's author.

| Model | Licence | Card |
| --- | --- | --- |
| Parakeet TDT v3 | CC BY 4.0 | [FluidInference/parakeet-tdt-0.6b-v3-coreml](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml) |
| Parakeet Ultra | CC BY 4.0 | [FluidInference/parakeet-ultra-coreml](https://huggingface.co/FluidInference/parakeet-ultra-coreml) |
| Parakeet EOU 120M | NVIDIA Open Model License | [FluidInference/parakeet-realtime-eou-120m-coreml](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml) |
| Nemotron Streaming EN | NVIDIA Open Model License | [FluidInference/nemotron-speech-streaming-en-0.6b-coreml](https://huggingface.co/FluidInference/nemotron-speech-streaming-en-0.6b-coreml) |
| Nemotron 3.5 Multilingual | OpenMDW-1.1 | [FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML](https://huggingface.co/FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML) |
| Parakeet Unified 0.6B | NVIDIA Open Model License | [FluidInference/parakeet-unified-en-0.6b-coreml](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml) |
| Whisper Tiny, Whisper Base, Whisper Small, Whisper Large v3 Turbo | MIT | [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml) |

The models are the work of NVIDIA (Parakeet and Nemotron) and OpenAI (Whisper), converted to Core ML by
[FluidInference](https://huggingface.co/FluidInference) (Parakeet and Nemotron) and Argmax (Whisper). The CC BY 4.0
entries are NVIDIA's Parakeet TDT v3, with its Core ML conversion by FluidInference, and Parakeet Ultra, a post-training
of it by Moondream (<https://huggingface.co/moondream/parakeet-ultra>) that FluidInference converted. Parakeet Unified
0.6B is listed under NVIDIA's licence, which governs NVIDIA's weights, although FluidInference's converted card says
CC BY 4.0.

## LiteLLM model prices

The price table of the Usage page (`src/usage/prices.generated.ts`) is a subset of
[LiteLLM](https://github.com/BerriAI/litellm)'s `model_prices_and_context_window.json`: the chat models of Anthropic,
OpenAI and Google, converted to US dollars per million tokens by `src/usage/update-prices.ts` (`pnpm prices:update`).
Copyright (c) 2023 Berri AI, under the MIT licence:

```
MIT License

Copyright (c) 2023 Berri AI

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

The prices are LiteLLM's reading of each provider's public price page, an estimate and not a bill. The table is copied, not
fetched at run time; refresh it with `pnpm prices:update` and commit the result.
