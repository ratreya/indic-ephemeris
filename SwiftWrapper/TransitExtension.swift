//
//  TransitExtension.swift
//  SwiftEphemeris
//
//  Created by Atreya Ranganath on 7/13/20.
//  Copyright © 2020 Daivajnanam. All rights reserved.
//

import Foundation

/**
 We are sampling position at 30 degrees (1 house) of spatial granularity.
 So, temporal sampling should be at that interval within which the planet will move less than 30 degrees.
 - Note: Max speed used for calculations in comments
 */
let sampling: [Planet: Calendar.Component] = [
    .Moon: .day,        // 20.81 degrees per day
    .Mercury: .day,     // 2.22 degrees per day
    .Venus: .day,       // 1.27 degrees per day
    .Sun: .day,         // 1.04 degrees per day
    .Mars: .month,      // 0.80 degrees per day
    .Jupiter: .month,   // 0.25 degrees per day
    .Saturn: .month,    // 0.14 degrees per day
    .NorthNode: .year,  // 0.07 degrees per day
    .SouthNode: .year   // 0.07 degrees per day
]

extension IndicEphemeris {
    static let granularityOrder: [Calendar.Component] = [.year, .month, .day, .hour, .minute, .second]
    
    internal func refineEdge(transit house: House, in range: DateInterval, for planet: Planet, from unit: Calendar.Component) throws -> Date? {
        if unit == .second { return range.start }
        let next = IndicEphemeris.granularityOrder[IndicEphemeris.granularityOrder.firstIndex(of: unit)!.advanced(by: 1)]
        let timePositions = try positions(for: planet, during: range, every: 1, unit: next)
        if let index = try timePositions.firstIndex(where: { try $0.1.houseLocation().house == house }) {
            if index == 0 { return timePositions[index].0 }
            return try refineEdge(transit: house, in: DateInterval(start: timePositions[index - 1].0, end: timePositions[index].0.advanced(by: 1)), for: planet, from: next)
        }
        return nil
    }
    
    public func transit(of planet: Planet, through house: House) throws -> [DateInterval] {
        let dailyPositions = try positions(for: planet, during: DateInterval(start: dateUTC, duration: lifetimeInSeconds), every: 1, unit: sampling[planet]!)
        var result = [DateInterval]()
        var intervalStart: Date? = nil
        for index in dailyPositions.indices {
            let (day, position) = dailyPositions[index]
            let currentHouse = try position.houseLocation().house
            if currentHouse == house, intervalStart == nil {
                intervalStart = index == 0 ? day : try refineEdge(transit: house, in: DateInterval(start: dailyPositions[index-1].0, end: day.advanced(by: 1)), for: planet, from: sampling[planet]!)!
            }
            if let start = intervalStart, currentHouse != house {
                let refined = try refineEdge(transit: currentHouse, in: DateInterval(start: dailyPositions[index-1].0, end: day.advanced(by: 1)), for: planet, from: sampling[planet]!)!
                result.append(DateInterval(start: start, end: refined))
                intervalStart = nil
            }
        }
        return result
    }
}
