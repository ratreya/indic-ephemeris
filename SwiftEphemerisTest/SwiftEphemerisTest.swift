//
//  SwiftEphemerisTest.swift
//  SwiftEphemerisTest
//
//  Created by Atreya Ranganath on 7/10/20.
//  Copyright © 2020 Daivajnanam. All rights reserved.
//

import XCTest
@testable import SwiftEphemeris

class SwiftEphemerisTest: XCTestCase {
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
}
