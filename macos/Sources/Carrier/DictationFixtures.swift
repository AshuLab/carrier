import CarrierCore
import Foundation

extension DictationController {
    /// What a `--fixture` build has dictated, so History and Statistics have something to draw: today's four outcomes (one cleaned, one with a long text, one
    /// that went to another app), and a few a day for the last 20 days, in a temporary folder like every fixture. The numbers are made up, not random, so a
    /// screenshot is the same each time.
    func seedFixtureDictations(now: Date = Date()) {
        let calendar = Calendar.current
        func at(daysAgo: Int, hour: Int, minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let long = "No, pero yo no quiero que use GitHub ni nada por el estilo. Mi idea es que tengamos un MCP el cual, cuando el usuario dice che, quiero hacer un sharpen de esto, sepa si utiliza el skill and the response that Sharpen, for example, those things in formato UI a little bit more linda. Y también, cuando se termina ese proceso, ya no hay más nada."
        var entries = [
            DictationEntry(started: at(daysAgo: 0, hour: 9, minute: 58), text: "Could not transcribe: the model is still loading", model: "Whisper large-v3", transcription: 0, audio: 4, destination: DictationEntry.widgetOnly, outcome: .failed),
            DictationEntry(started: at(daysAgo: 0, hour: 10, minute: 12), text: "Recuérdame que revise", model: "Parakeet TDT v3", transcription: 0.1, audio: 2, destination: DictationEntry.widgetOnly, outcome: .cancelled),
            DictationEntry(
                started: at(daysAgo: 0, hour: 10, minute: 41), text: "hey puedes revisar el pr de los selects cuando tengas un minuto creo que el margen quedo bien ahora",
                cleaned: "Hey, ¿puedes revisar el PR de los selects cuando tengas un minuto? Creo que el margen quedó bien ahora.", model: "Parakeet TDT v3", transcription: 0.4,
                cleanupModel: "Qwen 3 4B", cleanupSeconds: 1.8, audio: 9, destination: "Slack", outcome: .copied),
            DictationEntry(started: at(daysAgo: 0, hour: 10, minute: 53), text: long, model: "Parakeet TDT v3", transcription: 0.02, audio: 62, destination: DictationEntry.carrier, outcome: .pasted),
        ]
        let phrases = [
            "Revisa el margen de los selects en la pantalla de uso", "Add a switch to the keep awake page", "Muéstrame los commits de esta rama",
            "Run the tests and tell me what fails", "Cambia el color de acento a morado", "Write the changelog line for this fix",
        ]
        for day in 1...20 {
            for turn in 0..<(1 + day % 4) {
                let text = phrases[(day + turn) % phrases.count]
                entries.append(DictationEntry(
                    started: at(daysAgo: day, hour: 9 + (day * 3 + turn * 4) % 10, minute: (day * 7 + turn * 11) % 60), text: text + (day % 3 == 0 ? " " + text : ""),
                    model: day % 5 == 0 ? "Apple" : "Parakeet TDT v3", transcription: 0.3, audio: Double(3 + (day * 5 + turn * 9) % 40),
                    destination: turn % 2 == 0 ? "Carrier" : "Xcode", outcome: day % 7 == 0 ? .copied : .pasted))
            }
        }
        // oldest first, so each is the newest when it is recorded, as in a real history
        for entry in entries.sorted(by: { $0.started < $1.started }) { _ = records.record(entry) }
    }
}
