/*
* IndicEphemeris is a fluent Swift interface to Swiss Ephemeris with Indic Astrology specific extensions.
* Copyright (C) 2020 Ranganath Atreya
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
*/

import XCTest
@testable import IndicEphemeris

class TransitFinderTest: XCTestCase {
    var ephemeris: IndicEphemeris?
    
    override func setUpWithError() throws {
        ephemeris = IndicEphemeris(date: Date(timeIntervalSince1970: 1577836800), at: Place(placeId: "Ujjain", timezone: TimeZone(abbreviation: "IST")!, latitude: 23.2929831, longitude: 75.6256319, altitude: 478))
    }
    
    func testHouseRange() {
        let range = HouseRange(lowerBound: .Aquarius, count: 3)
        XCTAssert(!range.contains(.Sagittarius))
        XCTAssert(range.contains(.Aquarius))
        XCTAssert(range.contains(.Pisces))
        XCTAssert(range.contains(.Aries))
        XCTAssert(!range.contains(.Taurus))
        XCTAssert(!range.contains(.Cancer))
        XCTAssert(!range.contains(.Scorpio))
        
        XCTAssert(!range.degrees.contains(House.Sagittarius.degrees.lowerBound))
        XCTAssert(range.degrees.contains(House.Aquarius.degrees.lowerBound))
        XCTAssert(range.degrees.contains(House.Pisces.degrees.lowerBound))
        XCTAssert(range.degrees.contains(House.Aries.degrees.lowerBound))
        XCTAssert(!range.degrees.contains(House.Taurus.degrees.lowerBound))
        XCTAssert(!range.degrees.contains(House.Cancer.degrees.lowerBound))
        XCTAssert(!range.degrees.contains(House.Scorpio.degrees.lowerBound))

        let anti = range.inverted()
        XCTAssert(anti.contains(.Sagittarius))
        XCTAssert(!anti.contains(.Aquarius))
        XCTAssert(!anti.contains(.Pisces))
        XCTAssert(!anti.contains(.Aries))
        XCTAssert(anti.contains(.Taurus))
        XCTAssert(anti.contains(.Cancer))
        XCTAssert(anti.contains(.Scorpio))
    }
    
    func testDegreeRange() {
        let range = DegreeRange(lowerBound: 330, size: 60)
        XCTAssertTrue(range.contains(15))
        XCTAssertTrue(range.contains(355))
        XCTAssertFalse(range.contains(40))
        XCTAssertTrue(range.inverted().contains(45))
        XCTAssertFalse(range.inverted().contains(15))
        XCTAssertTrue(range.contains(0))
    }
    
    func testCalendarComponent() {
        for (index, granularity) in granularityOrder.enumerated() {
            if index > 0 {
                XCTAssert(granularity.isFiner(than: granularityOrder[index - 1]))
                XCTAssertEqual(granularity.nextCoarser, granularityOrder[index - 1])
            }
            if index < granularityOrder.count - 1 {
                XCTAssert(granularity.isCoarser(than: granularityOrder[index + 1]))
                XCTAssertEqual(granularity.nextFiner, granularityOrder[index + 1])
            }
        }
    }
    
    func testGranularity() {
        for index in 0..<granularityOrder.count-1 {
            let interval = Double.random(in: granularityOrder[index+1].seconds..<granularityOrder[index].seconds)
            XCTAssertEqual(interval.granularity.unit, granularityOrder[index+1], "\(interval)")
            XCTAssertGreaterThanOrEqual(interval.granularity.value, 1)
        }
    }
    
    func testPlanetarySpeeds() {
        for planet in Planet.allCases {
            var degrees = planet.avgDegrees(for: Calendar.Component.day.seconds)
            XCTAssertGreaterThan(degrees, 0)
            var time = planet.avgTime(for: degrees)
            XCTAssertEqual(time, Calendar.Component.day.seconds, accuracy: 0.000000001)
            degrees = planet.maxDegrees(for: Calendar.Component.day.seconds)
            XCTAssertGreaterThan(degrees, 0)
            time = planet.minTime(for: degrees)
            XCTAssertEqual(time, Calendar.Component.day.seconds, accuracy: 0.000000001)
        }
    }
    
    func testRefineEdge() throws {
        for planet in Planet.allCases {
            XCTAssertNotNil(try TransitFinder.refineEdge(using: ephemeris!, satisfying: { (pos: Position) -> Bool in return DegreeRange(lowerBound: 0, size: 90).contains(pos.longitude) }, during: DateInterval(start: Date(timeIntervalSince1970: 0), duration: planet.avgTime(for: 360)), for: planet, resolution: Calendar.Component.day))
        }
    }
    
    func testTransits() throws {
        let birth = Date(timeIntervalSinceNow: Double.random(in: 311040000...3110400000))
        let eph = IndicEphemeris(date: birth, at: Place(placeId: "Mysore", timezone: TimeZone(abbreviation: "IST")!, latitude: 12.3051828, longitude: 76.6553609, altitude: 746))
        let moon = try eph.position(for: .Moon).houseLocation().house
        let planet = Planet.allCases[(Int.random(in: 1..<9) + 1) % 9] // Random planet excluding the Moon
        let moonRange = HouseRange(adjoining: moon)
        let transits = try TransitFinder(eph).transits(of: planet, through: moonRange, limit: .count(from: birth, count: 3))
        for transit in transits {
            let timePositions = try eph.positions(for: planet, during: transit, every: 60*60)
            XCTAssert(timePositions.allSatisfy({(date, position) -> Bool in moonRange.degrees.contains(position.longitude)}), "Failed \(planet) for \(transit)")
        }
    }
    
    class TestConfig: Config {
        let definition: FringePolicy
        init(_ definition: FringePolicy) { self.definition = definition }
        override var retrogradeDefinition: FringePolicy { definition }
    }

    func testRetrograde() throws {
        for planet in Planet.allCases[2..<7] {
            let eph = IndicEphemeris(date: ephemeris!.dateUTC, at: ephemeris!.place, config: TestConfig(.strict))
            let retros = try TransitFinder(eph).retrogrades(of: planet, overlapping: DateInterval(start: Date(), duration: planet.synodicPeriod * 2))
            XCTAssertFalse(retros.isEmpty)
            for retro in retros {
                let timePositions = try eph.positions(for: planet, during: retro, every: 60*60)
                let predicate: ((Date, Position)) -> Bool = planet == .NorthNode ? { $0.1.speed! > 0 } : { $0.1.speed! < 0 }
                XCTAssert(timePositions.allSatisfy(predicate), "Failed \(planet) for \(retro).\n\(timePositions.map { "\($0.0): \($0.1.speed!)" }.joined(separator: "\n"))")
            }
        }
    }
}
