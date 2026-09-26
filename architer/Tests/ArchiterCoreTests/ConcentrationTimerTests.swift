import Foundation
import Testing
@testable import ArchiterCore

@Suite("Concentration duration timers (3.33.0)")
struct ConcentrationTimerTests {
    @Test func durationParsing() {
        #expect(Character.concentrationRounds(forDuration: "1 round") == 1)
        #expect(Character.concentrationRounds(forDuration: "3 rounds") == 3)
        #expect(Character.concentrationRounds(forDuration: "1 minute") == 10)
        #expect(Character.concentrationRounds(forDuration: "10 minutes") == 100)
        #expect(Character.concentrationRounds(forDuration: "1 hour") == 600)
        #expect(Character.concentrationRounds(forDuration: "2 Hours") == 1200)
        #expect(Character.concentrationRounds(forDuration: "Instantaneous") == nil)
        #expect(Character.concentrationRounds(forDuration: "Until dispelled") == nil)
        #expect(Character.concentrationRounds(forDuration: "") == nil)
    }

    @Test func tickDecrementsAndExpires() {
        var c = Character(name: "T")
        c.beginConcentration(on: "Faerie Fire")
        c.concentrationTimer = 2
        let first = c.tickConcentrationTimer()
        #expect(first == nil)
        #expect(c.concentrationTimer == 1 && c.concentratingOn == "Faerie Fire")
        let second = c.tickConcentrationTimer()
        #expect(second == "Faerie Fire")
        #expect(c.concentrationTimer == nil && c.concentratingOn == nil)
        let third = c.tickConcentrationTimer()
        #expect(third == nil) // no timer: no-op
    }

    @Test func exitPathsClearTimer() {
        var c = Character(name: "T")
        c.beginConcentration(on: "A")
        c.concentrationTimer = 5
        c.dropConcentration()
        #expect(c.concentrationTimer == nil)
        c.concentrationTimer = 5
        c.beginConcentration(on: "B")
        #expect(c.concentrationTimer == nil) // fresh concentration resets
        #expect(c.concentratingOn == "B")
    }

    @Test func legacySaveDecodesWithoutTimer() throws {
        var c = Character(name: "T")
        c.beginConcentration(on: "A")
        c.concentrationTimer = 4
        let data = try JSONEncoder().encode(c)
        var obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj.removeValue(forKey: "concentrationTimer")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(Character.self, from: stripped)
        #expect(decoded.concentrationTimer == nil)
        #expect(decoded.concentratingOn == "A")
    }
}
