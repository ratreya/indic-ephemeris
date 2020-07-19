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
            _ = try eph.transit(of: Planet.allCases[Int.random(in: 0..<9)], through: HouseRange(adjoining: moon), during: DateInterval(start: Date(), duration: Double.random(in: 31104000...311040000)))
        }
    }
    
    func testDashas() throws {
        let range = DateInterval(start: Date(), duration: 30*24*60*60)
        print(range)
        print(try ephemeris!.dashas(overlapping: range).map( { $0.description } ).joined(separator: "\n"))
        print(try ephemeris!.position(for: .Moon).nakshatraLocation())
        print(try ephemeris!.dashas().map( { $0.description } ).joined(separator: "\n"))
    }
}
