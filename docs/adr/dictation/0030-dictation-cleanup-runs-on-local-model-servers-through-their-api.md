# 0030 - Dictation cleanup runs on local model servers through their API, not on agent CLIs

- Status: proposed
- Date: 2026-11-16

## Context

The owner wants the text of a dictation to go through a language model before it lands: remove filler words, translate to English, make it more technical, explain it better, all by one prompt that he writes. It applies where he dictates, in the global widget and in the message boxes.

Carrier's providers are agent CLIs (Claude Code, Codex, Antigravity), driven headless as agents with tools; LM Studio and Ollama appear only as servers that feed those agents their models. There is no call in Carrier that takes text and gives text. Running a cleanup through an agent starts an agent per dictation, which is seconds of waiting before the paste, and hands what the person said to something that can run commands: a dictated "delete that file" would be input to an agent, not text to clean.

## Decision

The cleanup talks to a local model server, LM Studio or Ollama, through its HTTP API on this Mac, with the person's prompt as the system message and the dictated text as the user message, no tools. The person chooses the server and the model in the Dictation page and writes one prompt in a text box; the cleanup is off until they do. If the server is down, the model is missing or the call times out, the raw text is used as the result and the widget or the box says it could not be cleaned. Cloud models come later, through their APIs and not through the CLIs.

## Alternatives considered

An agent CLI per dictation. It is the person's own account and models, and it is slow and gives dictated words the reach of an agent with tools.

An agent CLI with its tools off. It removes the risk and keeps the cost of starting a process and a session for every paste.

A cloud API from the first cut. It reaches better models, and it needs keys that Carrier does not hold, since it keeps logins and not keys, and it sends what the person said off the Mac by default.

Named presets of prompts, picked per dictation. Useful if the person switches between translating and cleaning all day; he said he does not, so it is one prompt and presets wait for a reason.

## Consequences

Cleanup needs a model running locally. Whether a small local model does well enough with Spanish and English mixed, and how long the wait between the end of a dictation and the paste is, are measured before the slice is built.

The message box gets one more state after transcribing, cleaning, and `DictationSession` carries it. The raw and the cleaned text are both kept in the history ([0031](0031-dictation-keeps-a-history-and-its-statistics-live-apart-from-it.md)).

A failure of the cleanup never loses the dictation, and the cause goes to `dictation.log` like any other.
