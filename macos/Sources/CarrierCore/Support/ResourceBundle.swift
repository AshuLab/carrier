import Foundation

/// CarrierCore's resource bundle (the file and provider icons). SwiftPM's `Bundle.module` looks next to the `.app`, not in
/// `Contents/Resources` where `build-app.sh` puts it, and it traps when it finds nothing, so the packaged app crashed on
/// the first icon. Look in `Contents/Resources` first; `Bundle.module` stays the answer for `swift run` and the tests.
let carrierResources: Bundle = {
    if let url = Bundle.main.resourceURL?.appendingPathComponent("Carrier_CarrierCore.bundle"),
        let bundle = Bundle(url: url)
    {
        return bundle
    }
    return Bundle.module
}()
