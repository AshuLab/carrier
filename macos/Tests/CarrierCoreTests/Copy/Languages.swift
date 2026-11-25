import Foundation

@testable import CarrierCore

// The two languages a test renders in. A function that builds a sentence takes `bundle:` and `locale:` (defaults: the app's language), so a test passes them:
//     startingSteps(epic, reply: nil, now: 0, bundle: english.bundle, locale: english.locale)
// English words are asserted with `english`, and Spanish ones with `spanish` (Argentina, whose numbers group with a dot).
let english = (bundle: Copy.bundle("en"), locale: Locale(identifier: "en_US"))
let spanish = (bundle: Copy.bundle("es"), locale: Locale(identifier: "es_AR"))
