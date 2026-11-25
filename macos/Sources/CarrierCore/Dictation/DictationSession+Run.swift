import Foundation
import Observation

extension DictationSession {
    func transcribe() {
        state = .transcribing
        answerIsSlow = false
        let mine = generation, quick = Self.quickAnswer
        slowness = Task {
            guard await pause(quick), generation == mine else { return }
            answerIsSlow = true
        }
    }

    /// Waits for `duration` on the session's clock; false when the wait was cancelled.
    private func pause(_ duration: Duration) async -> Bool {
        do { try await sleep(duration) } catch { return false }
        return true
    }

    func waitForTheAnswer() {
        let mine = generation
        let timeout = Self.answerFloor + Self.answerPerAudioSecond * captured.components.seconds
        watchdog = Task {
            guard await pause(timeout), Task.isCancelled == false, generation == mine else { return }
            running?.cancel()
            fail(DictationFailure("The recognizer did not answer."))
        }
    }

    /// A model that is not ready past the floor is a dictation that could not start, and what was heard is dropped.
    /// The task is never cancelled: when it wakes it checks that this dictation is still the current one and that the model is still not ready.
    private func watchTheModel(_ mine: Int) {
        let floor = Self.answerFloor
        Task {
            guard await pause(floor), generation == mine, modelReady == false, state != .idle else { return }
            samples = []
            running?.cancel()
            fail(DictationFailure("The speech model did not get ready in time."))
        }
    }

    func run(_ recognizer: any Recognizer, _ model: SpeechModel, _ mine: Int) async {
        // a dictation ended before this task began never touches the capture
        guard generation == mine else { return }
        let audio: AsyncStream<AudioBuffer>
        do { audio = try capture.start() } catch {
            fail(error)
            return
        }
        timings.capture = milliseconds(since: began)
        state = .listening
        announce(dictationAnnouncement(.listening))
        // the recognizer reads the audio through a stream that counts it, and that keeps what the capture gives, in order, until the recognizer reads it
        let counted = AsyncStream<AudioBuffer> { continuation in
            let relay = Task { @MainActor in
                for await buffer in audio {
                    // a dictation that ended while a buffer was on its way leaves the next one its own times and samples
                    guard generation == mine else { break }
                    if timings.firstAudio == nil {
                        timings.firstAudio = milliseconds(since: began)
                        onListening?()
                    }
                    captured += .seconds(Double(buffer.samples.count) / buffer.sampleRate)
                    if recording {
                        samples += buffer.samples
                        sampleRate = buffer.sampleRate
                    }
                    continuation.yield(buffer)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in relay.cancel() }
        }
        watchTheModel(mine)
        await beforePrepare()
        guard generation == mine else { return }
        do {
            try await recognizer.prepare(model)
        } catch {
            if generation == mine { fail(error) }
            return
        }
        guard generation == mine else { return }
        timings.modelReady = milliseconds(since: began)
        modelReady = true
        if stopped {
            // stopped while the model loaded: what was captured is read now, and the person already stopped, so it never looks like listening again
            transcribe()
            waitForTheAnswer()
        }
        for await event in recognizer.recognize(counted) {
            guard generation == mine else { return }
            if case .failed(let failure) = event {
                fail(failure)
                return
            }
            if let field, let edit = tentative.apply(event, to: field.text(), caret: field.caret()) {
                switch event {
                case .partial(let firm, let tentative):
                    let heard = firm + tentative
                    noteFirstWord(heard)
                    partialWords = wordCount(heard)
                    partial = heard
                case .final(let heard):
                    noteFirstWord(heard)
                    words += wordCount(heard)
                    partialWords = 0
                    partial = ""
                    finals.append(heard)
                case .failed: break
                }
                field.put(edit.text, edit.caret, tentative.tentativeRange)
            }
        }
        guard generation == mine else { return }
        if let stoppedAt { timings.finalText = milliseconds(since: stoppedAt) }
        await clean(mine)
        // a cleanup that failed has told its cause, which is not a stop
        if generation == mine { end(announcing: failure == nil) }
    }

    /// Replaces the text this dictation added with the cleaned one, in the state `.cleaning`, which a skip, a failure and a text that changed meanwhile
    /// leave as it was: the raw text is never lost.
    private func clean(_ mine: Int) async {
        // the recognizer has answered: the time it was given is spent, and the cleanup has its own
        watchdog?.cancel()
        watchdog = nil
        slowness?.cancel()
        guard let cleanup, let field else { return }
        settle()
        guard let range = tentative.written else { return }
        let ns = field.text() as NSString
        guard NSMaxRange(NSRange(location: range.lowerBound, length: range.count)) <= ns.length else { return }
        let added = ns.substring(with: NSRange(location: range.lowerBound, length: range.count))
        guard added.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        state = .cleaning
        let cleaned: String
        let cleaningFrom = now()
        do { cleaned = try await cleanup(added) } catch {
            guard generation == mine, let owner else { return }
            refuse(DictationFailure((error as? CleanupFailure)?.message ?? error.localizedDescription), for: owner)
            return
        }
        guard generation == mine else { return }
        let text = field.text() as NSString
        let place = NSRange(location: range.lowerBound, length: range.count)
        guard NSMaxRange(place) <= text.length, text.substring(with: place) == added else { return }
        // the cleanup trims, and a space that set the dictation apart from the words around it is not its text
        let raw = added.trimmingCharacters(in: .whitespacesAndNewlines), bounds = added.range(of: raw)!
        let replacement = added[..<bounds.lowerBound] + cleaned.trimmingCharacters(in: .whitespacesAndNewlines) + added[bounds.upperBound...]
        let caret = field.caret(), delta = (replacement as NSString).length - place.length
        field.put(
            text.replacingCharacters(in: place, with: String(replacement)),
            caret <= place.location ? caret : caret >= NSMaxRange(place) ? caret + delta : place.location + (replacement as NSString).length, nil
        )
        words = wordCount(cleaned)
        self.cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanupSeconds = now().timeIntervalSince(cleaningFrom)
    }

    /// A partial text on the screen stays, as final, and its words count.
    private func settle() {
        guard let field else { return }
        if tentative.range != nil {
            words += partialWords
            partialWords = 0
            finals.append(partial)
            partial = ""
            tentative.close()
        }
        field.put(field.text(), field.caret(), nil)
    }

    private func noteFirstWord(_ heard: String) {
        if timings.firstWord == nil, wordCount(heard) > 0 { timings.firstWord = milliseconds(since: began) }
    }

    func milliseconds(since start: Date) -> Int { Int((now().timeIntervalSince(start) * 1000).rounded()) }

    private func wordCount(_ heard: String) -> Int { heard.split(whereSeparator: \.isWhitespace).count }

    private func fail(_ error: Error) {
        let cause = error as? DictationFailure ?? DictationFailure(error.localizedDescription)
        if let owner { refuse(cause, for: owner) }
        end(.failed, announcing: false)
    }

    /// Back to idle: the audio is dropped, and a partial text on the screen is kept as final.
    func end(_ ending: DictationTake.Ending = .stopped, announcing: Bool = true) {
        capture.stop()
        let modelName = model?.name ?? ""
        // the range is cleared even when the person's edit had already ended the writing
        settle()
        if announcing, state == .listening || state == .transcribing || state == .cleaning { announce(dictationAnnouncement(.stopped(words: words))) }
        watchdog?.cancel()
        watchdog = nil
        slowness?.cancel()
        answerIsSlow = false
        running = nil
        field = nil
        model = nil
        cleanup = nil
        if timings.isEmpty == false { timed(timings) }
        let finished = owner
        owner = nil
        generation += 1
        state = .idle
        let ended = now()
        let heard = DictationTake(
            owner: finished, started: began, text: finals.filter { $0.isEmpty == false }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines), model: modelName,
            audio: captured.inSeconds,
            transcription: stoppedAt.map { ended.timeIntervalSince($0) } ?? 0, ending: ending,
            cleaned: cleaned, cleanupSeconds: cleanupSeconds, clip: recording && samples.isEmpty == false ? AudioClip(samples: samples, sampleRate: sampleRate) : nil)
        samples = []
        take = heard
        onTake?(heard)
        onEnd?(finished)
        if let next = queued {
            queued = nil
            start(recognizer: next.recognizer, model: next.model, into: next.field, cleanup: next.cleanup)
        }
    }
}
