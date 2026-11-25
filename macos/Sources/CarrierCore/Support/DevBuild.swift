import Foundation

/// Set by build-app.sh when no version is given: this is a development build, not the installed Carrier.
public let isDevBuild = Bundle.main.object(forInfoDictionaryKey: "CarrierChannel") as? String == "dev"
