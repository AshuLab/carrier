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
        SettingsGroup(id: "sounds", title: Copy.dictationGroupSounds(), footer: Copy.dictationSoundsFooter()) {
            soundRow(id: "start-sound", Copy.dictationStartSound(), detail: Copy.dictationStartSoundDetail(), on: $startOn, name: $start, first: true)
            soundRow(id: "end-sound", Copy.dictationEndSound(), detail: Copy.dictationEndSoundDetail(), on: $endOn, name: $end)
            SettingsTabRow(id: "volume", title: Copy.dictationVolume(), detail: Copy.dictationVolumeDetail(volume: volume)) {
                Slider(value: Binding(get: { Double(volume) }, set: { volume = Int($0.rounded()) }), in: 0...100)
                    .labelsHidden().frame(width: settingsSliderWidth).accessibilityLabel(Copy.dictationVolume()).accessibilityValue(Copy.dictationVolumePercent(volume: volume))
            }
        }
    }

    private func soundRow(id: String, _ title: String, detail: String, on: Binding<Bool>, name: Binding<String>, first: Bool = false) -> some View {
        SettingsTabRow(id: id, title: title, detail: detail, first: first) {
            HStack(spacing: Tokens.Space.s8) {
                IconButton(icon: .playFilled, name: Copy.dictationPlay(title: title)) { DictationSoundPlayer.play(SoundToPlay(name: name.wrappedValue, volume: Double(volume) / 100)) }
                ChoicePopUp(label: title, options: dictationSoundChoices.map { (value: $0, title: $0) }, selection: name)
                Toggle(title, isOn: on).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}
