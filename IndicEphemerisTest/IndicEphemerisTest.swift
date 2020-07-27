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
        XCTAssertLessThan(abs(try ephemeris!.julianDay() - 2458849.2708333), 0.0001)
    }
    
    func testMoon() throws {
        XCTAssertLessThan(abs(try ephemeris!.position(for: .Moon).longitude - 319.27), 1)
        XCTAssertEqual(try ephemeris!.position(for: .Moon).nakshatraLocation().nakshatra, Nakshatra.Shatabhisha)
    }

    func testAscendent() throws {
        XCTAssertLessThan(abs(try ephemeris!.ascendant().longitude - 158.96), 1)
    }
    
    func testAllPositions() throws {
        for planet in Planet.allCases {
            print("\(planet): \(try ephemeris!.position(for: planet).houseLocation())")
        }
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
        let anti = range.inverted()
        XCTAssert(anti.contains(.Sagittarius))
        XCTAssert(!anti.contains(.Aquarius))
        XCTAssert(!anti.contains(.Pisces))
        XCTAssert(!anti.contains(.Aries))
        XCTAssert(anti.contains(.Taurus))
        XCTAssert(anti.contains(.Cancer))
        XCTAssert(anti.contains(.Scorpio))
    }
    
    func testHouseMath() {
        XCTAssertEqual(House.Aries + 1, House.Taurus)
        XCTAssertEqual(House.Aries - 1, House.Pisces)
        XCTAssertEqual(House.Aries - 13, House.Pisces)
        XCTAssertEqual(House.Aries + 13, House.Taurus)
    }
    
    func testTransits() throws {
        for _ in 0...10 {
            let birth = Date(timeIntervalSinceNow: Double.random(in: 311040000...3110400000))
            let eph = IndicEphemeris(date: birth, at: Place(placeId: "Mysore", timezone: TimeZone(abbreviation: "IST")!, latitude: 12.3051828, longitude: 76.6553609, altitude: 746))
            let moon = try eph.position(for: .Moon).houseLocation().house
            _ = try TransitFinder(eph).transits(of: Planet.allCases[Int.random(in: 0..<9)], through: HouseRange(adjoining: moon), limit: .duration(DateInterval(start: Date(), duration: Double.random(in: 31104000...311040000))))
        }
    }
    
    func testDashas() throws {
        let range = DateInterval(start: Date(), duration: 30*24*60*60)
        print(range)
        print(try DashaCalculator(ephemeris!).dashas(overlapping: range).map( { $0.description } ).joined(separator: "\n"))
        print(try ephemeris!.position(for: .Moon).nakshatraLocation())
        print(try DashaCalculator(ephemeris!).dashas().map( { $0.description } ).joined(separator: "\n"))
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
    
    func testRetrograde() throws {
        for planet in Planet.allCases[...7] {
            let secsPerRev = planet.avgTime(for: 20)
            let retros = try TransitFinder(ephemeris!).retrogrades(of: planet, during: DateInterval(start: Date(), duration: secsPerRev))
            for retro in retros {
                let timePositions = try ephemeris!.positions(for: planet, during: retro, every: 60*60)
                let predicate: ((Date, Position)) -> Bool = planet == .NorthNode ? { $0.1.speed! > 0 } : { $0.1.speed! < 0 }
                XCTAssert(timePositions.allSatisfy(predicate), "Failed \(planet) for \(retro)")
            }
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
    
    func XXXtestGetRetrograde() throws {
        for planet in Planet.allCases[...7] {
            let secsPerRev = planet.avgTime(for: 360 * 10)
            let interval = DateInterval(start: Date(timeIntervalSinceReferenceDate: 0).advanced(by: -secsPerRev), duration: secsPerRev * 2)
            let timePositions = try TransitFinder(ephemeris!).retrogrades(of: planet, during: interval)
            let max = timePositions.map { $0.duration }.max()
            let midpoints = timePositions.map { $0.start.advanced(by: $0.duration/2) }
            let diffs = stride(from: 0, to: midpoints.count - 1, by: 1).map { (midpoints[$0 + 1].timeIntervalSince1970 - midpoints[$0].timeIntervalSince1970) }
            print("\(planet): \(max ?? 0) (\((max ?? 0).degreeMinuteSecond), \(diffs.max() ?? 0) (\((diffs.max() ?? 0).degreeMinuteSecond)")
            
        }
    }
}
