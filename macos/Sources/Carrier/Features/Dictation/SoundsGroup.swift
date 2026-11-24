import CarrierCore
import SwiftUI

/// The Sounds group of the page: a start and an end sound of the global dictation, each on or off, one of macOS's own and a play button, and one volume
/// for both. With Dictation off the group is drawn at 40%.
struct SoundsGroup: View {
    @AppStorage(Preference.dictationSoundStartOn) private var startOn
    @AppStorage(Preference.dictationSoundStart) private var start
    @AppStorage(Preference.dictationSoundEndOn) private var endOn
    @AppStorage(Preference.dictationSoundEnd) private var end
    @AppStorage(Preference.dictationSoundVolume) private var volume

    var body: some View {
        SettingsGroup(title: "Sounds", footer: "Tink, Pop or Glass. The play button always plays, at the volume set; the message boxes stay silent.") {
            soundRow("Start sound", detail: "Plays when it begins to listen", on: $startOn, name: $start, first: true)
            soundRow("End sound", detail: "Plays when it stops listening and goes on to clean and paste", on: $endOn, name: $end)
            SettingsTabRow(title: "Volume", detail: "For both sounds, in the global dictation only; \(volume)%") {
                Slider(value: Binding(get: { Double(volume) }, set: { volume = Int($0.rounded()) }), in: 0...100)
                    .labelsHidden().frame(width: settingsSliderWidth).accessibilityLabel("Volume").accessibilityValue("\(volume) percent")
            }
        }
    }

    private func soundRow(_ title: String, detail: String, on: Binding<Bool>, name: Binding<String>, first: Bool = false) -> some View {
        SettingsTabRow(title: title, detail: detail, first: first) {
            HStack(spacing: 8) {
                IconButton(icon: .playFilled, name: "Play \(title)") { DictationSoundPlayer.play(SoundToPlay(name: name.wrappedValue, volume: Double(volume) / 100)) }
                ChoicePopUp(label: title, options: dictationSoundChoices.map { (value: $0, title: $0) }, selection: name)
                Toggle(title, isOn: on).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}
