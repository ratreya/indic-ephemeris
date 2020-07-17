//
//  TransitExtension.swift
//  SwiftEphemeris
//
//  Created by Atreya Ranganath on 7/13/20.
//  Copyright © 2020 Daivajnanam. All rights reserved.
//

import Foundation

public struct HouseRange {
    let lowerBound: House
    let count: Int
    let constituent: Set<House>

    public init(lowerBound: House, count: Int) {
        self.lowerBound = lowerBound
        self.count = count
        self.constituent = Set(Array(0..<count).map({ House(rawValue: (lowerBound.rawValue + $0) % 12)! }))
    }
    
    public func contains(_ house: House) -> Bool { constituent.contains(house) }
    public func inverted() -> HouseRange { HouseRange(lowerBound: lowerBound + count, count: 12-count) }
}

extension IndicEphemeris {
    static let granularityOrder: [Calendar.Component] = [.year, .month, .day, .hour, .minute, .second]
    
    internal func refineEdge(transit houses: HouseRange, in range: DateInterval, for planet: Planet, from unit: Calendar.Component) throws -> Date? {
        if unit == .second { return range.start }
        let next = IndicEphemeris.granularityOrder[IndicEphemeris.granularityOrder.firstIndex(of: unit)!.advanced(by: 1)]
        let timePositions = try positions(for: planet, during: range, every: 1, unit: next)
        if let index = try timePositions.firstIndex(where: { try houses.contains($0.1.houseLocation().house) }) {
            if index == 0 { return timePositions[index].0 }
            return try refineEdge(transit: houses, in: DateInterval(start: timePositions[index - 1].0, end: timePositions[index].0.advanced(by: 1)), for: planet, from: next)
        }
        return nil
    }
    
    public func transit(of planet: Planet, through houses: HouseRange, during range: DateInterval) throws -> [DateInterval] {
        let timePositions = try positions(for: planet, during: range, every: 1, unit: planet.sampling)
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
