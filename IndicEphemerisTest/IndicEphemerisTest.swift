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

class IndicEphemerisTest: XCTestCase {
    var ephemeris: IndicEphemeris?
    
    override func setUpWithError() throws {
        ephemeris = IndicEphemeris(date: Date(timeIntervalSince1970: 1577836800), at: Place(placeId: "Ujjain", timezone: TimeZone(abbreviation: "IST")!, latitude: 23.2929831, longitude: 75.6256319, altitude: 478))
    }

    func testJulianDate() throws {
        XCTAssertEqual(try ephemeris!.julianDay(), 2458849.2708333, accuracy: 0.00001)
        let us = IndicEphemeris(date: Date(timeIntervalSince1970: 1577836800), at: Place(placeId: "San Francisco", timezone: TimeZone(abbreviation: "PST")!, latitude: 37.774929, longitude: -122.419418, altitude: 16))
        XCTAssertEqual(try us.julianDay(), 2458849.8333333, accuracy: 0.00001)
    }
    
    func testMoon() throws {
        XCTAssertEqual(try ephemeris!.position(for: .Moon).longitude, 319.27, accuracy: 1)
        XCTAssertEqual(try ephemeris!.position(for: .Moon).nakshatraLocation().nakshatra, Nakshatra.Shatabhisha)
    }

    func testAscendent() throws {
        XCTAssertEqual(try ephemeris!.ascendant().longitude, 158.96, accuracy: 1)
    }
    
    func testAllPositions() throws {
        for planet in Planet.allCases {
            print("\(planet): \(try ephemeris!.position(for: planet).houseLocation())")
        }
    }
    
    func testHouseMath() {
        XCTAssertEqual(House.Aries + 1, House.Taurus)
        XCTAssertEqual(House.Aries - 1, House.Pisces)
        XCTAssertEqual(House.Aries - 13, House.Pisces)
        XCTAssertEqual(House.Aries + 13, House.Taurus)
    }
    
    func testDashas() throws {
        let dashas = try DashaCalculator(ephemeris!).vimshottari()
        XCTAssertEqual((dashas.prenatal + dashas.postnatal).reduce(into: 0) { $0 += $1.period.duration }, 120 * Calendar.Component.year.seconds)
    }
    
    func testGranularity() throws {
        for unit in granularityOrder {
            XCTAssertEqual(unit.seconds.granularity.value, 1)
            XCTAssertEqual(unit.seconds.granularity.unit, unit)
            XCTAssertEqual((unit.seconds * 7).granularity.value, 7)
            XCTAssertEqual((unit.seconds * 7).granularity.unit, unit)
            XCTAssertEqual((unit.seconds * 100).granularity.unit, granularityOrder[max(granularityOrder.firstIndex(of: unit)!.advanced(by: -1), 0)])
        }
    }
    
    func testProlepticDate() throws {
        var date = ISO8601DateFormatter().date(from: "1582-10-01T00:00:00+0000")!
        for _ in 0..<30 {
            let old = try ephemeris!.julianDay(for: date)
            print("\(date): \(old)")
            date = date.advanced(by: Calendar.Component.day.seconds)
            let new = try ephemeris!.julianDay(for: date)
            print("\(date): \(new)")
            XCTAssertEqual(old, new - 1)
        }
    }
    
    func testProlepticDateGap() throws {
        let date = ISO8601DateFormatter().date(from: "1582-10-10T00:00:00+0000")!
        XCTAssertEqual(try ephemeris!.julianDay(for: date), 2299165.5)
    }

    func XXXtestGetSpeeds() throws {
        for planet in Planet.allCases[...7] {
            let secsPerRev = planet.avgTime(for: 360 * 50)
            let sampling = planet.minTime(for: 1)
            let interval = DateInterval(start: Date(timeIntervalSinceReferenceDate: 0).advanced(by: -secsPerRev), duration: secsPerRev)
            let speeds = try ephemeris!.mapReduce(during: interval, map: { (ephemeris: IndicEphemeris, range: DateInterval) -> [Double] in
                let positions = try ephemeris.positions(for: planet, during: range, every: sampling)
                return positions.map { $0.1.speed! }
            }, reduce: {(shard: [Double], previous: inout [Double]?) in
                if previous == nil { previous = [] }
                previous!.append(contentsOf: shard)
            })
            let average = (speeds as NSArray).value(forKeyPath: "@avg.floatValue") as! Double
            print("Planet: \(planet), Average \(String(format: "%.6f", average)), Max: \(String(format: "%.6f", speeds.max()!))")
        }
    }
    
    func testPerson() throws {
        let date = ISO8601DateFormatter().date(from: "1977-06-09T20:50:00+0000")!
        let place = Place(placeId: "Hyderabad", timezone: TimeZone(abbreviation: "IST")!, latitude: Double(degree: 17, minute: 23, second: 3), longitude: Double(degree: 78, minute: 27, second: 23), altitude: 515)
        let eph = IndicEphemeris(date: date, at: place)
        XCTAssertEqual(try eph.ascendant().longitude, 263.67, accuracy: 0.1)
        XCTAssertEqual(try eph.position(for: .Moon).longitude, 337.09, accuracy: 0.1)
    }
}
