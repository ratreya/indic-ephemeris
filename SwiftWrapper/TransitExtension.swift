/*
* IndicEphemeris is a fluent Swift interface to Swiss Ephemeris with Indic Astrology specific extensions.
* Copyright (C) 2020 Ranganath Atreya
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
*/

import Foundation

public struct HouseRange: CustomStringConvertible {
    let lowerBound: House
    let count: Int
    let constituent: Set<House>
    
    public var description: String { constituent.description }

    public init(lowerBound: House, count: Int) {
        self.lowerBound = lowerBound
        self.count = count
        self.constituent = Set(Array(0..<count).map({ lowerBound + $0 }))
    }
    
    public init(adjoining house: House) {
        self.init(lowerBound: house-1, count: 3)
    }
    
    public func contains(_ house: House) -> Bool { constituent.contains(house) }
    public func inverted() -> HouseRange { HouseRange(lowerBound: lowerBound + count, count: 12-count) }
}

let granularityOrder: [Calendar.Component] = [.year, .month, .day, .hour, .minute, .second]

extension IndicEphemeris {
    internal func refineEdge(transit houses: HouseRange, in range: DateInterval, for planet: Planet, from unit: Calendar.Component) throws -> Date? {
        let unitIndex = granularityOrder.firstIndex(of: unit)!
        if unitIndex <= granularityOrder.firstIndex(of: config.transitResolution)! { return range.start }
        let next = granularityOrder[unitIndex.advanced(by: 1)]
        let timePositions = try positions(for: planet, during: range, every: 1, unit: next)
        if let index = try timePositions.firstIndex(where: { try houses.contains($0.1.houseLocation().house) }) {
            if index == 0 { return timePositions[index].0 }
            return try refineEdge(transit: houses, in: DateInterval(start: timePositions[index - 1].0, end: timePositions[index].0.advanced(by: 1)), for: planet, from: next)
        }
        return nil
    }
    
    public func transit(of planet: Planet, through houses: HouseRange, during range: DateInterval) throws -> [DateInterval] {
        let timePositions = try positions(for: planet, during: range, every: houses.count, unit: planet.sampling)
        var result = [DateInterval]()
        var intervalStart: Date? = nil
        for index in timePositions.indices {
            let (time, position) = timePositions[index]
            let currentHouse = try position.houseLocation().house
            if houses.contains(currentHouse), intervalStart == nil {
                intervalStart = index == 0 ? time : try refineEdge(transit: houses, in: DateInterval(start: timePositions[index-1].0, end: time.advanced(by: 1)), for: planet, from: planet.sampling)!
            }
            if let start = intervalStart, !houses.contains(currentHouse) {
                let refined = try refineEdge(transit: houses.inverted(), in: DateInterval(start: timePositions[index-1].0, end: time.advanced(by: 1)), for: planet, from: planet.sampling)!
                result.append(DateInterval(start: start, end: refined))
                intervalStart = nil
            }
        }
        return result
    }
    
    public func transit(of planet: Planet, through houses: HouseRange) throws -> [DateInterval] {
        return try transit(of: planet, through: houses, during: DateInterval(start: dateUTC, duration: lifetimeInSeconds))
    }
}
