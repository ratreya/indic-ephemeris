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
        XCTAssertEqual(try ephemeris!.julianDay(), 2458849.2708333, accuracy: 0.0001)
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
    
    func testNonProlepticDate() throws {
        let date = ISO8601DateFormatter().date(from: "1300-02-29T10:10:00+0000")!
        _ = try ephemeris?.julianDay(for: date)
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
        let date = ISO8601DateFormatter().date(from: "1987-08-04T18:18:00+0000")!
        let place = Place(placeId: "Bengaluru", timezone: TimeZone(abbreviation: "IST")!, latitude: 12.97082225, longitude: 77.58582276, altitude: 918)
        let eph = IndicEphemeris(date: date, at: place)
        let moon = try eph.position(for: .Moon)
        print(try TransitFinder(eph).transits(of: .Saturn, through: HouseRange(adjoining: moon.houseLocation().house), limit: .count(from: Date().advanced(by: -Calendar.Component.year.seconds), count: 1)))
        print(try DashaCalculator(eph).vimshottari())
    }
}
