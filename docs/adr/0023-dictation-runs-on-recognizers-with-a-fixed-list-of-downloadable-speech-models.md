# 0023 - Dictation runs on recognizers with a fixed list of downloadable speech models

- Status: accepted
- Date: 2026-11-12

## Context

Carrier has no voice input. The owner dictates today with an external app, FluidVoice, on Parakeet TDT v3, in a mix of Spanish and English, and wants to stop using it: one tool, and a feature any person who uses Carrier can use, not only him. The first cut is a button in the chat composer; a shortcut and typing into other apps come next, then cleanup with a language model and a personal dictionary.

The speech models that matter differ in what they need. Apple's SpeechAnalyzer is managed by the system and has no download. FluidAudio runs Parakeet and Nemotron through CoreML, from files of 250 to 670 MB, and gives partial text natively on some and none on the batch ones; a batch model that is fast enough (Parakeet TDT v3 runs at over a hundred times real time) can show partial text if the audio so far is transcribed again at short intervals, which is what FluidVoice and Handy do. Whisper has its own models and its own libraries. The Apple recognizer has no published latency or error figures, and nobody has measured it in Spanish here.

Carrier is MIT. FluidVoice, whose catalog and structure are the closest to what we want, is GPL-3.0, so its code cannot be reused; Handy is MIT but is Rust and Tauri.

## Decision

Dictation lives in a core in `CarrierCore`, with no interface of its own, behind one boundary: a recognizer, which says which speech models it offers, takes audio and gives text events, and states how it gives partial text (natively, by the core's chunking, or none). The first cut has three recognizers: Apple's SpeechAnalyzer, FluidAudio and Whisper. The person picks a recognizer and then a model of it.

The speech models are one fixed list in the app's code, with a record per model: recognizer, size, languages, how it gives partial text, licence and where it is downloaded from. The page that shows it can be filtered by recognizer. A model is downloaded by the person from that page, never ships with the app, and nothing outside the list can be downloaded: no free URL, no arbitrary repository. Adding a model is an app update.

The first use works with Apple's recognizer, with no download, so the button never sits there doing nothing until 500 MB arrive. A person who wants Parakeet downloads it and picks it. The downloaded models are kept in the Carrier folder ([0016](0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md)), in `app/models/<recognizer>/<model>/`: the app is the third process that owns a subfolder, and the libraries are pointed there instead of at where each puts its files by default. A model is downloaded only by an explicit action of the person, with the libraries' own downloaders (they resume, retry and report progress) aimed at that folder; the libraries are told never to fetch by themselves when they load a model, so nothing is ever downloaded unasked.

The chunking that gives a fast batch model its partial text is ours, in the core, and is the same for any recognizer that needs it.

## Alternatives considered

Apple's recognizer alone. It is the cheapest cut, with no dependency and nothing to download, but it would be a step back from what the owner uses now and we cannot yet say how it does in Spanish.

One recognizer without a boundary, FluidAudio only. Smaller, but the owner asked to choose the recognizer and the model, and a second recognizer added later would have to cut the first one open.

Bundling the models with the app. It adds hundreds of megabytes to every download and update, and a Homebrew cask that downloads them anyway would be hiding a cost the person did not choose.

Letting the person point to any model, by URL or repository. It reaches every model, but it downloads code-adjacent files nobody on our side has looked at, in formats a recognizer may not load, and it moves the support from our list to the person's choice. A fixed list is an allowlist, and a model we have not tried does not get in.

Starting with the global dictation, which is what lets the owner switch the external app off. It is the larger and riskier piece: it needs the Accessibility permission, a global key and typing into other apps, all of which depend on how the app is signed ([0017](0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md)). The owner chose the in-app button first, on a core that already holds what the global one needs.

Reusing FluidVoice's code. Its licence, GPL-3.0, would force the whole app under it. It is read for ideas only.

Whisper through whisper.cpp or transcribe.cpp. Both are MIT and run on Metal, but neither has a maintained SwiftPM package (the one that exists for transcribe.cpp is a mirror by one person, two commits and behind its upstream), they have no Core ML path, and the download code would be ours. WhisperKit has a Swift API, Core ML and a downloader.

## Consequences

There are three recognizers to keep working, each with its own dependency, its own manager for each model and its own way of failing. FluidAudio's code is Apache-2.0, and the Whisper recognizer is WhisperKit (argmax-oss-swift): its code is MIT, its Whisper weights are MIT, and it carries one vendored Apache-2.0 part; the paid tier of that company is a separate SDK that nothing here pulls in. The models' licences are not the code's: Parakeet TDT v3 is CC-BY-4.0, Parakeet EOU and Nemotron EN use NVIDIA's open model licence, and Nemotron 3.5 Multilingual uses OpenMDW-1.1. Carrier redistributes no weights, since the person downloads them from Hugging Face, which is what keeps the attribution duties of those licences from being Carrier's; the list shows each model's licence with a link to its card, and `THIRD-PARTY-NOTICES.md` names the libraries and the models.

The core carries a chunking layer with its own question to answer: whether the partial text it gives is steady and what it costs in processor time. A model too slow for it, such as the large Whisper models, gives its text at the end.

The first cut asks the system for the microphone only. With the ad hoc signing of [0017](0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md), macOS may forget a permission when Sparkle replaces the app; for the microphone that is a new prompt, and it is to be measured. For the Accessibility permission of the global dictation it is a heavier cost, and that decision is left to its own epic.

The list is only as fresh as the app. A new model reaches people with an update.
