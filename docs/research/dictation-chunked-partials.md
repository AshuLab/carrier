# Spike: partial text from a fast model that does not stream

Answers the second open question of [the dictation spec](../specs/dictation-in-the-app.md) (issue #857, epic #856): can the core make steady partial text by transcribing the audio so far at short intervals, how often, which words does it hold as settled, what does it cost, and which models are fast enough. It writes no production code. The harness, the clips and the models live outside the repository.

## The answer

**Policy.** Every second of audio, and also at every pause, transcribe the current segment again from its start and show the whole result as the tentative text. A segment is the audio since the last pause that closed one. A pause of 150 ms or more after at least 300 ms of speech (the capture's level below -45 dBFS) closes the segment: the text of that last pass is settled, the audio of the segment is dropped and the next pass starts from nothing. If a segment reaches 12 s without a pause, settle by agreement: the words that two passes in a row start with, minus the last two, become settled, and the audio is cut at the middle of the gap after the last settled word. The stop does one more pass over what is not settled and the text is final. A pass never overlaps another: when one is late the next starts when it ends, so a slow Mac gets longer intervals, never a backlog.

**Numbers for it on Parakeet TDT v3** (six clips of about 20 s, Spanish and English, interval 1 s): 17.7% of the words shown later changed or disappeared, and 5.3% were rewritten further back than the last two words; the words a person ends up with differ from what was said by 0.2% (word error rate); a word appears 0.30 s after it ended on average (0.96 s in the worst clip's 95th percentile); processor time is 0.048 s per second of audio when passes run back to back and 0.109 s per second in real time with idle gaps; the model is busy 6% to 12% of the time; after the stop the final text arrives within 0.08 s (0.10 s in real time).

**The rule.** A model gets partial text by chunks when one pass over 10 s of audio, measured with a second of idle between passes, has a real-time factor of 0.05 or less (a pass of 0.5 s or less, so that at a 1 s interval the model is busy at most half the time). Over that the text comes at the end. On this machine (M2 Max):

| model | real-time factor, one pass over 10 s | side |
|---|---|---|
| Parakeet TDT v3 (FluidAudio) | 0.015 | by chunks |
| Whisper tiny (WhisperKit) | 0.024 to 0.032 | by chunks |
| Whisper small | 0.062 to 0.083 | at the end |
| Whisper large v3 turbo (632 MB quantized) | 0.088 to 0.107 | at the end |

**Parakeet TDT v3 keeps the label Live.** Whisper small is on the other side of the line, which the spec did not expect; see "What changes in the spec".

## How it was measured

- Machine: Apple M2 Max, 32 GB, macOS 27.0, Swift 6.4.2. Everything below is one machine; a slower Mac moves every model towards the end of the table.
- Libraries: FluidAudio 0.18.3 and argmax-oss-swift (WhisperKit) 1.1.1, the versions that `macos/Package.swift` pins on the branch of #858 (`feat/dictation-in-the-app/858-dependencies-and-build-for-dictation`, commit e2c0022). Parakeet TDT v3 is `parakeet-tdt-0.6b-v3` (469 MB on disk). The Whisper models are `openai_whisper-tiny` (73 MB), `openai_whisper-small` (465 MB) and `openai_whisper-large-v3-v20240930_turbo_632MB` (624 MB), the quantized large v3 turbo. WhisperKit base was not measured (the ticket asks for tiny, small and large).
- Harness: a SwiftPM package of its own in a scratch folder, one executable that loads a model, feeds a clip to a policy and writes a JSON line per run. Parakeet is called with `AsrManager.transcribe(samples)` and Whisper with `WhisperKit.transcribe(audioArrays:)` with the language set, no word timestamps unless the policy needs them. The words and their times of Parakeet come from its token timings, those of Whisper from its word timestamps.
- Clips, made with `say` at 16 kHz mono: `es` (voice Monica, 19.7 s) and `en` (Samantha, 21.0 s), a sentence of about 70 words each about reviewing a branch before pushing it; `es-nopause` and `en-nopause` (18.0 s and 19.2 s), the same text with the commas, full stops and colon taken out so the voice runs on; `es2` (Paulina, 24.5 s) and `en2` (Reed, 23.4 s), the same text in other voices; and `long` (79.9 s), the four first clips one after the other with half a second between, to see what happens to the cost when a dictation is long. The spoken text is the reference of the word error rate.
- Real time: the audio is cut at the moments the policy asks for passes. The main sweep runs on a virtual clock: the pass really runs, its real duration is measured, and the model is busy for that long on the clip's timeline, so a slow model falls behind exactly as it would. The recommended policy was also run in real time, sleeping between passes, on the `es` and `en` clips and every model, to check the virtual clock (results below).
- Steadiness, the share of words shown that later changed or disappeared: each display is the list of words on screen (letters and digits only, lowercase). Between two displays the words that are the same from the start are untouched; the words of the earlier display after that point are counted as changed or disappeared and the words of the new display after that point as shown again. The share is changed over shown. "Deep" counts only the words that changed further back than the last two words of the earlier display, because the tail is still forming in any recognizer; it is the part a person reads as the text rewriting itself.
- Word delay: the first display with at least i+1 words, minus the moment word i ended, where the moment comes from Parakeet's token timings on the whole clip. It is by word count, so it is only trusted when the text is right; for `long` it is not trusted (the timings of one 80 s pass drift) and is not reported.
- Processor time is `getrusage` of the process (user plus system) over the run, divided by the seconds of audio. The Neural Engine and the GPU, where Core ML runs most of these models, do not show in it, and no energy was measured (`powermetrics` needs root). The figure says how much the cores are used, not what the battery pays.

## Real-time factor of one pass

One pass over the first N seconds of a clip, plain transcription, median of 7 passes after a discarded one (time of the pass divided by N). Back to back, then, for 10 s, with a second of idle between passes (12 passes, median), which is how a pass runs once a second:

| model | clip | 3 s | 10 s | 19 s | 10 s with idle | 10 s with word timestamps |
|---|---|---|---|---|---|---|
| Parakeet TDT v3 | es | 0.0186 | 0.0084 | 0.0087 | 0.0155 | n/a |
| | en | 0.0179 | 0.0083 | 0.0082 | 0.0152 | n/a |
| Whisper tiny | es | 0.0338 | 0.0279 | 0.0273 | 0.0321 | 0.0357 |
| | en | 0.0242 | 0.0201 | 0.0176 | 0.0236 | 0.0237 |
| Whisper small | es | 0.1058 | 0.0800 | 0.0739 | 0.0825 | 0.0913 |
| | en | 0.0854 | 0.0562 | 0.0496 | 0.0618 | 0.0661 |
| Whisper large v3 turbo | es | 0.2170 | 0.1047 | 0.0858 | 0.1070 | 0.1119 |
| | en | 0.1910 | 0.0854 | 0.0627 | 0.0880 | 0.0893 |

A pass over 10 s takes 0.083 s with Parakeet (0.15 s with idle), 0.20 to 0.28 s with tiny, 0.56 to 0.80 s with small and 0.85 to 1.05 s with the large turbo. The cost grows with the audio (tiny 0.10 s at 3 s and 0.52 s at 19 s in Spanish), which is why dropping audio matters for every model, not only Parakeet. Parakeet does the work of a pass in about a hundred times less than real time, as the ADR says; with idle between passes it is about sixty times.

First load of a model (download plus Core ML compile on the first run): Parakeet 55.8 s, tiny 26.9 s, small 64.7 s, large turbo 250.9 s. A second load: Parakeet 0.09 s, tiny 4.5 s, small 4.9 s, large turbo 7.4 s. The first pass after loading was not slower than the next ones beyond noise (WhisperKit prewarmed at load).

## The policies tried (Parakeet TDT v3)

Six clips (`es`, `en`, `es-nopause`, `en-nopause`, `es2`, `en2`), mean of the clips, virtual clock. Changed is the share of words shown that later changed or disappeared, deep the part of them further back than the last two words, WER the word error rate of the final text against what was spoken, cpu the processor seconds per second of audio, busy the share of time spent inside a pass, max buffer the longest audio a pass was given, delay the mean word delay and, after the slash, the worst 95th percentile among the clips, stop the longest wait from the end of the audio to the final text.

- `whole`: every pass is the whole audio so far, nothing is settled.
- `agree0`, `agree2`: no pauses. The words two passes in a row start with, minus 0 or 2, are settled and the audio before them is dropped.
- `pause150`, `pause250`: pause of 150 ms or 250 ms closes the segment (a pass at the moment of the pause), no other drop.
- `hyb150-8-2`, `hyb150-12-2`, `hyb250-12-2`: pause of 150 or 250 ms, and the agreement rule with the last two words kept back when the segment reaches 8 or 12 s. `hyb150-12-2` is the recommendation.

| policy | T s | changed % | deep % | WER % | cpu | busy | max buffer s | delay s | stop s |
|---|---|---|---|---|---|---|---|---|---|
| whole | 0.5 | 25.7 | 4.9 | 0.0 | 0.292 | 0.199 | 24.5 | 0.06 / 0.58 | 0.32 |
| whole | 1 | 17.5 | 3.9 | 0.0 | 0.156 | 0.107 | 24.5 | 0.30 / 1.09 | 0.30 |
| whole | 2 | 10.4 | 2.2 | 0.0 | 0.084 | 0.056 | 24.5 | 0.76 / 2.05 | 0.30 |
| agree0 | 0.5 | 46.3 | 22.1 | 13.4 | 0.065 | 0.108 | 5.6 | n/a | 0.06 |
| agree0 | 1 | 41.6 | 23.3 | 11.7 | 0.042 | 0.063 | 5.9 | n/a | 0.05 |
| agree0 | 2 | 17.4 | 9.3 | 1.4 | 0.025 | 0.030 | 8.1 | 0.76 / 1.90 | 0.05 |
| agree2 | 0.5 | 55.7 | 30.0 | 9.1 | 0.075 | 0.115 | 5.4 | n/a | 0.06 |
| agree2 | 1 | 38.8 | 23.3 | 5.0 | 0.047 | 0.065 | 6.8 | 0.29 / 2.14 | 0.06 |
| agree2 | 2 | 24.5 | 15.8 | 1.2 | 0.029 | 0.033 | 10.4 | 0.79 / 2.64 | 0.07 |
| pause150 | 0.5 | 28.0 | 6.5 | 0.0 | 0.091 | 0.112 | 12.6 | 0.07 / 0.52 | 0.07 |
| pause150 | 1 | 16.7 | 4.6 | 0.0 | 0.050 | 0.059 | 12.5 | 0.32 / 0.96 | 0.07 |
| pause150 | 2 | 7.4 | 2.4 | 0.0 | 0.031 | 0.036 | 12.5 | 0.81 / 1.89 | 0.07 |
| pause250 | 0.5 | 26.3 | 5.8 | 0.0 | 0.185 | 0.153 | 19.7 | 0.04 / 0.59 | 0.29 |
| pause250 | 1 | 13.6 | 2.4 | 0.0 | 0.096 | 0.079 | 19.7 | 0.34 / 1.08 | 0.30 |
| pause250 | 2 | 7.0 | 0.9 | 0.0 | 0.054 | 0.043 | 19.7 | 0.81 / 2.00 | 0.30 |
| hyb150-8-2 | 1 | 20.1 | 7.8 | 0.2 | 0.046 | 0.058 | 8.0 | 0.30 / 0.96 | 0.07 |
| hyb250-12-2 | 1 | 15.3 | 3.9 | 0.5 | 0.059 | 0.064 | 12.0 | 0.30 / 0.96 | 0.09 |
| **hyb150-12-2** | 0.5 | 28.7 | 7.2 | 0.2 | 0.090 | 0.111 | 12.0 | 0.05 / 0.52 | 0.07 |
| **hyb150-12-2** | **1** | **17.7** | **5.3** | **0.2** | **0.048** | **0.059** | **12.0** | **0.30 / 0.96** | **0.08** |
| **hyb150-12-2** | 2 | 8.8 | 3.6 | 0.2 | 0.028 | 0.033 | 12.0 | 0.79 / 1.89 | 0.06 |

(The delay is not reported where its mean came out negative, words shown before they were spoken, which happens when the text has extra wrong words and the count-based delay stops meaning anything.)

Reading it:

- **The pauses are what makes dropping audio safe.** Cutting the audio in the middle of speech by agreement alone (`agree0`, `agree2`) is the cheapest and the worst: 39% to 56% of the words change at 1 s and 0.5 s, about half of them rewritten far back, and 5% to 13% of the words of the final text are wrong, because the short tail that remains has lost its context. Cutting at a pause (`pause150`) costs nothing in accuracy (0.0% against what was said) and is as steady as transcribing the whole audio every time (16.7% against 17.5% at 1 s).
- **Transcribing the whole audio every time (`whole`) is the steadiest and the most expensive, and it breaks on a long dictation.** On the 80 s clip at 1 s it uses 0.569 s of processor per second of audio against 0.047 for the recommendation, the pass takes up to 80 s of audio, 52.0% of the words change and 44.1% of them far back, probably because Parakeet takes 15 s at a time (`maxModelSamples` is 240000 samples) and the rest is stitched from chunks, and the final text has 2.9% wrong words. The cost of `whole` grows with the dictation; the recommendation's does not.
- **150 ms over 250 ms.** With 250 ms the clips close 12 segments instead of 27, the longest pass gets 19.7 s of audio instead of 12.5 s and the stop waits 0.30 s instead of 0.07 s, for slightly fewer changes (13.6% against 16.7% at 1 s). Both are close; 150 ms bounds the cost better.
- **The agreement fallback is rare and cheap.** In the six clips it settled words once (the 12.5 s segment without a pause, `en-nopause`) and twice in `long`; the WER of the final text goes from 0.0% to 0.2% (0.0% to 0.7% on `long`). With a fallback at 8 s it settles more often and the deep share goes from 5.3% to 7.8%, so 12 s is better; it is also under the 15 s window of the model.
- **Interval.** At 0.5 s the text changes more (28.7%, 7.2% deep) for a delay of 0.05 s. At 2 s it is steadier (8.8%, 3.6% deep) but the words arrive in blocks of about five (95th percentile 1.9 s). One second is the middle: mean delay 0.30 s, 95th percentile under one second, and the model is busy 6% of the time.

Per clip, the recommended policy at 1 s: changed 6.7% (`en`) to 25.8% (`es2`) and deep 0.0% (`en`) to 9.2% (`en-nopause`); the spread between clips is larger than the difference between the policies that sit close together, so differences of a few points above are not findings. The `long` clip: 18.4% changed, 5.0% deep, 0.7% WER, 0.047 cpu, 0.058 busy.

### Holding back the last words

The display can leave out the last h words of the tentative text until a later pass has moved past them (the stop pass shows all). The recommended policy, six clips:

| T s | words held back | changed % | deep % | mean word delay s |
|---|---|---|---|---|
| 1 | 0 | 17.7 | 5.3 | 0.30 |
| 1 | 1 | 9.7 | 2.5 | 0.54 |
| 1 | 2 | 6.1 | 0.6 | 0.77 |

It halves the changes for a quarter of a second more of delay. It is a choice of the box, not of the chunking, and is not recommended as the default: the spec already draws the tentative text secondary, and the words that change are the ones just spoken.

### The virtual clock against real time

The recommended policy at 1 s, `es` and `en` clips, once on the virtual clock and once in real time (the passes really spaced by the clock):

| model | run | changed % | deep % | WER % | cpu | busy | delay s (mean / worst p95) | stop s |
|---|---|---|---|---|---|---|---|---|
| Parakeet TDT v3 | virtual | 13.2 | 2.3 | 0.0 | 0.045 | 0.059 | 0.37 / 0.96 | 0.05 |
| | real time | 14.1 | 2.4 | 0.0 | 0.109 | 0.123 | 0.42 / 1.03 | 0.10 |
| Whisper tiny | virtual | 24.4 | 13.6 | 8.7 | 0.052 | 0.084 | 0.62 / 1.81 | 0.07 |
| | real time | 27.7 | 15.4 | 8.7 | 0.120 | 0.198 | 0.69 / 1.90 | 0.19 |
| Whisper small | virtual | 32.9 | 17.3 | 24.6 | 0.325 | 0.538 | 0.85 / 1.97 | 0.76 |
| | real time | 15.5 | 4.4 | 2.9 | 0.293 | 0.482 | 0.89 / 2.05 | 0.33 |
| Whisper large v3 turbo | virtual | 6.0 | 0.0 | 0.0 | 0.149 | 0.669 | 1.24 / 2.33 | 1.52 |
| | real time | 4.8 | 0.0 | 0.0 | 0.155 | 0.679 | 1.29 / 2.36 | 1.44 |

The text and the delays agree. The cost does not for Parakeet and tiny: with a pause of a second between passes Parakeet and tiny cost twice as much per pass as back to back (the Neural Engine and the GPU going idle and waking up), which is why the real-time factor of the rule is the one with idle. Use the real-time figure as the processor time of the feature: **0.109 s of processor per second of audio for Parakeet, about 11% of one core while listening, plus the Neural Engine**. Whisper small gave 24.6% wrong words in one run and 2.9% in the other: the agreement fallback with Whisper's word timestamps is not reliable (see below).

## The other models

The recommended policy at intervals of 1 s and 2 s, the six clips, virtual clock. The word delay is by count and the worst 95th percentile among the clips, so large turbo's 7.0 s means a clip where it fell behind.

| model | T s | changed % | deep % | WER % | cpu | busy | delay s | stop s (worst) |
|---|---|---|---|---|---|---|---|---|
| Parakeet TDT v3 | 1 | 17.7 | 5.3 | 0.2 | 0.048 | 0.059 | 0.30 / 0.96 | 0.08 |
| | 2 | 8.8 | 3.6 | 0.2 | 0.028 | 0.033 | 0.79 / 1.89 | 0.06 |
| Whisper tiny | 1 | 27.4 | 14.8 | 11.8 | 0.055 | 0.089 | 0.67 / 2.15 | 0.14 |
| | 2 | 18.4 | 9.7 | 11.5 | 0.038 | 0.061 | 0.90 / 2.19 | 0.16 |
| Whisper small | 1 | 27.7 | 15.2 | 11.1 | 0.289 | 0.485 | 0.87 / 2.43 | 1.22 |
| | 2 | 13.4 | 6.6 | 4.1 | 0.140 | 0.250 | 1.09 / 2.51 | 1.06 |
| Whisper large v3 turbo | 1 | 13.9 | 5.9 | 1.4 | 0.193 | 0.746 | 1.52 / 7.04 | 3.65 |
| | 2 | 9.7 | 5.8 | 1.2 | 0.115 | 0.473 | 1.68 / 4.87 | 2.71 |

For comparison, the same Whisper models with the whole audio every time or with the pause only, on `es` and `en`, at 1 s: tiny `whole` busy 0.194, stop 0.43 s; small `whole` busy 0.675, stop 1.63 s; large turbo `whole` busy 0.892, stop 2.24 s; large turbo `pause150` busy 0.860, stop 2.02 s. The large turbo model is busy 67% to 89% of the time at a 1 s interval and the stop waits 1.4 s to 3.7 s for the pass in flight and the last one; small is at 48% to 54% with a stop of up to 1.2 s in its worst clip (2.0 s with the pause only); tiny and Parakeet are at 6% to 20% with a stop under 0.2 s. Between 20% and 48% of busy time there is no model measured: the line of the rule falls in that gap.

Whisper tiny is fast but not steady (14.8% deep at 1 s) and not accurate (11.8% wrong words over the six clips, 6.5% for a pass over the whole audio of `es` and `en`); the agreement fallback sits on Whisper's word timestamps and with small it gave 24.6% wrong words in one run and 2.9% in another on the same clips, so it is not to be trusted with Whisper; for Whisper models the fallback may need a longer segment (the window is 30 s) or timestamps from another source, which this spike did not try.

## The rule

By chunks when the real-time factor of one pass over 10 s of audio, with a second of idle between passes, is **0.05 or less**.

Why that number: the policy asks for a pass every second, and a pass that takes more than half of the interval leaves the model with no room, so the stop waits behind a pass in flight and the words arrive late. Half a second for a pass over 10 s is 0.05. The runs agree with the line: every model under it (Parakeet, tiny) was busy at most 20% of the time with a stop under 0.2 s; every model over it (small, large turbo) was busy 48% to 89%, with a worst-clip stop of 1.2 s (small) and 3.7 s (large turbo) and a mean word delay of 0.85 s to 1.5 s. The 10 s of audio is the longest a pass sees with the 12 s fallback. The measure has to be taken with idle between passes (without it Parakeet looks 1.8 times faster and tiny 1.2 times).

| model | measured | side |
|---|---|---|
| Parakeet TDT v3 | 0.015 | by chunks |
| Whisper tiny | 0.024 to 0.032 | by chunks (speed); steadiness short of the bar, see below |
| Whisper small | 0.062 to 0.083 | at the end |
| Whisper large v3 turbo | 0.088 to 0.107 | at the end |

Models not measured (Whisper base, Parakeet EOU, Nemotron and the rest of FluidAudio's list) are put on a side by running the same measure on them, which the catalog check can do. Whisper base should land between tiny and small and is the one to measure first.

## Does Parakeet TDT v3 keep the label Live?

Yes. A model carries Live when it is fast enough by the rule and the words shown are steady enough, and steady enough is set here at: no more than 30% of the words shown change later and no more than 10% change further back than the last two words, at the 1 s interval, on every clip. These two numbers are a judgement; no native streaming recognizer was measured to calibrate them and no one watched the text. Parakeet with the recommended policy: 17.7% and 5.3% on average, 25.8% and 9.2% in its worst clips, a mean word delay of 0.30 s and a final text that is as right as one pass over the whole audio (0.2% against the spoken text). The tail words change and the rest do not: about two thirds of the changes are in the last two words.

Whisper tiny passes the speed rule but not the steadiness bar at 1 s (27.4% and 14.8%); at 2 s it is nearer (18.4%, 9.7%) and its accuracy stays the same, 11.5% wrong words. By the spec's own sentence, that a model that is not steady gets When you stop, tiny is on the By chunks side for speed and should carry When you stop for steadiness at the recommended interval.

## What changes in the spec

- The spec says the small Whisper models get partial text from the core. At 1 s they do not (real-time factor 0.062 to 0.083; busy about half the time; stop up to 1.2 s in the worst clip). Whisper small with an interval of 2 s works (busy 25%, 13.4% changed, 6.6% deep, 4.1% wrong words, mean delay 1.09 s) but would mean an interval per model; the recommendation keeps one interval, so Whisper small is `atTheEnd`. The catalog and the spec's list of "how it gives partial text" should say so, or the team accepts a second interval for the models between 0.05 and 0.10.
- FluidAudio throws `invalidAudioData` on less than 0.3 s of audio (`ASRConstants.minimumAudioDurationSeconds`). The harness pads every buffer with silence to 1 s; the core must not call it with less than 0.3 s of audio, and while the buffer holds less than 0.3 s of speech it should not ask for a pass at all (the harness skips the pass, which also keeps the cost down in a silence).
- The 15 s that Parakeet takes in one go is a reason for the 12 s of the fallback; for Whisper the window is 30 s.

## Tests of story 6

The chunking layer is a pure function of the audio's level, the passes of a scripted recognizer and a clock, so these hold whatever the numbers turn out to be on a given Mac and can be written from this document:

- A pass is requested at every 1 s of audio, and at the moment a pause of 150 ms ends after 300 ms of speech; two passes never overlap and a late pass is followed by the next one when it ends (no backlog).
- A closing pause settles the text of the last pass of the segment, drops its audio, and the next pass receives only audio after the pause; the settled text is never changed again.
- A segment of 12 s with no pause settles the words that two passes in a row start with minus the last two, cuts the audio at the middle of the gap after the last settled word and keeps the rest tentative; with fewer than two agreed words it settles nothing.
- While the audio of the segment is under 0.3 s of speech no pass is requested; a buffer under 0.3 s is never given to a recognizer.
- The stop requests one pass over what is not settled and the display ends with the settled text followed by it, a `final`; with no speech at all it is `final("")`.
- A word already settled is never lost, and the displayed text is always the settled words followed by the tentative ones, which a new pass replaces whole.
- A model on the at-the-end side gets no pass until the stop.

## What this does not cover

- No real person speaking. The six clips are synthetic voices, clean, with silences that are digital silence, and the pause detection at -45 dBFS only had to find silences like that. Real speech has a noise floor and breath; the pause threshold of the real capture has to be relative to the noise floor, and the 150 ms may need to be longer. Pauses between words of a real speaker may close a segment too early; the cost of that is only that a segment's words are settled when a pause was not a pause. The owner's own dictation and Apple's recognizer in Spanish are not measured here.
- The steadiness is on about 70 words per clip and six clips; clips differ by 25 points in the share of words changed, so nothing under five points is a finding.
- One Mac. One language per run: Whisper was given the language, so its Automatic detection, which can change from one pass to the next on a short buffer, was not tried. Parakeet was run with no language, as it detects it.
- Native streaming recognizers (Apple, Nemotron, Parakeet EOU) were not measured, so the bar of "steady" has no reference.
- Energy was not measured, only processor time.
