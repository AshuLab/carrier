import Foundation
import Testing

@testable import CarrierCore

@Suite struct TypeScaleTests {
    @Test func a_hundred_percent_returns_the_base() {
        for base in [9, 10, 11, 11.5, 12, 14, 16, 26] as [CGFloat] { #expect(TypeScale(percent: 100).size(base) == base) }
    }

    @Test func the_ends_scale_and_round_to_half_a_point() {
        #expect(TypeScale(percent: 130).size(14) == 18)    // 18.2
        #expect(TypeScale(percent: 130).size(12) == 15.5)  // 15.6
        #expect(TypeScale(percent: 90).size(14) == 12.5)   // 12.6
        #expect(TypeScale(percent: 90).size(11.5) == 10.5) // 10.35
    }

    @Test func a_percent_outside_the_range_is_clamped() {
        #expect(TypeScale(percent: 50).percent == 90)
        #expect(TypeScale(percent: 200).percent == 130)
        var scale = TypeScale()
        scale.percent = 500
        #expect(scale.percent == 130)
    }

    @Test func it_reads_the_percent_from_the_preferences() {
        let defaults = UserDefaults(suiteName: "TypeScaleTests-\(UUID().uuidString)")!
        #expect(TypeScale.stored(in: defaults).percent == 100)
        defaults.set(120, forKey: TypeScale.percentKey)
        #expect(TypeScale.stored(in: defaults).percent == 120)
        defaults.set("big", forKey: TypeScale.percentKey)
        #expect(TypeScale.stored(in: defaults).percent == 100)
    }
}
