import CarrierCore
import SwiftUI

/// The one door the views use to read and write a preference: `@AppStorage(Preference.density) private var density`.
/// `PreferenceKey` is named with its module here because SwiftUI has a protocol of the same name.
/// An unset key gives the key's default, a stored value its value, and a stored value that is not one of an enum's cases gives the default.
/// `store` is for a test's scratch defaults; the app passes none and gets the standard ones.
extension AppStorage {
    public init(_ key: CarrierCore.PreferenceKey<Value>, store: UserDefaults? = nil) where Value == Bool {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }

    public init(_ key: CarrierCore.PreferenceKey<Value>, store: UserDefaults? = nil) where Value == Int {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }

    public init(_ key: CarrierCore.PreferenceKey<Value>, store: UserDefaults? = nil) where Value == Double {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }

    public init(_ key: CarrierCore.PreferenceKey<Value>, store: UserDefaults? = nil) where Value == String {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }

    public init(_ key: CarrierCore.PreferenceKey<Value>, store: UserDefaults? = nil) where Value: RawRepresentable, Value.RawValue == String {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }

    /// A preference with no value of its own reads as nil while none is saved; nil on a binding takes the saved value out.
    public init(_ key: OptionalPreferenceKey<Bool>, store: UserDefaults? = nil) where Value == Bool? {
        self.init(key.name, store: store)
    }

    public init(_ key: OptionalPreferenceKey<String>, store: UserDefaults? = nil) where Value == String? {
        self.init(key.name, store: store)
    }

    public init<Wrapped>(_ key: OptionalPreferenceKey<Wrapped>, store: UserDefaults? = nil) where Value == Wrapped?, Wrapped: RawRepresentable, Wrapped.RawValue == String {
        self.init(key.name, store: store)
    }
}
