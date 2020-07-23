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

public enum TransitLimit {
    case count(from: Date, count: Int)
    case duration(DateInterval)
}

extension Calendar.Component {
    var seconds: TimeInterval {
        Calendar.current.date(byAdding: self, value: 1, to: Date(timeIntervalSince1970: 0))!.timeIntervalSince1970
    }
}

extension DateInterval {
    static func + (right: DateInterval, left: TimeInterval) -> DateInterval {
        DateInterval(start: right.start, duration: right.duration + left)
    }
}

extension Planet {
    /**
     Returns the rate of temporal sampling needed to make sure that you get at least one position per given number of spatial degrees.
     */
    func sampling(degrees: Double) -> (value: Int, unit: Calendar.Component) {
        let seconds = degrees/self.maxSpeed * 24 * 60 * 60
        for i in stride(from: granularityOrder.count-1, to: 0, by: -1) {
            if (granularityOrder[i].seconds..<granularityOrder[i-1].seconds).contains(seconds) {
                return (Int(seconds/granularityOrder[i].seconds), granularityOrder[i])
            }
        }
        return (Int(seconds/granularityOrder[0].seconds), granularityOrder[0])
    }
}

public class TransitFinder {
    private let ephemeris: IndicEphemeris

    public init(_ ephemeris: IndicEphemeris) {
        self.ephemeris = ephemeris
    }
    
    func refineEdge(using ephemeris: IndicEphemeris, transit houses: HouseRange, in range: DateInterval, for planet: Planet, from unit: Calendar.Component) throws -> Date? {
        let unitIndex = granularityOrder.firstIndex(of: unit)!
        if unitIndex <= granularityOrder.firstIndex(of: ephemeris.config.transitResolution)! { return range.start }
        let next = granularityOrder[unitIndex.advanced(by: 1)]
        let timePositions = try ephemeris.positions(for: planet, during: range, every: 1, unit: next)
        if let index = try timePositions.firstIndex(where: { try houses.contains($0.1.houseLocation().house) }) {
            if index == 0 { return timePositions[index].0 }
            return try refineEdge(using: ephemeris, transit: houses, in: DateInterval(start: timePositions[index - 1].0, end: timePositions[index].0.advanced(by: 1)), for: planet, from: next)
        }
        return nil
    }
    
    func transit(using ephemeris: IndicEphemeris, of planet: Planet, through houses: HouseRange, during range: DateInterval) throws -> [DateInterval] {
        let (count, unit) = planet.sampling(degrees: 30 * Double(houses.count))
        let timePositions = try ephemeris.positions(for: planet, during: range, every: count, unit: unit)
        var result = [DateInterval]()
        var intervalStart: Date? = nil
        for index in timePositions.indices {
            let (time, position) = timePositions[index]
            let currentHouse = try position.houseLocation().house
            if houses.contains(currentHouse), intervalStart == nil {
                intervalStart = index == 0 ? time : try refineEdge(using: ephemeris, transit: houses, in: DateInterval(start: timePositions[index-1].0, end: time.advanced(by: 1)), for: planet, from: unit)!
            }
            if let start = intervalStart, !houses.contains(currentHouse) {
                let refined = try refineEdge(using: ephemeris, transit: houses.inverted(), in: DateInterval(start: timePositions[index-1].0, end: time.advanced(by: 1)), for: planet, from: unit)!
                result.append(DateInterval(start: start, end: refined))
                intervalStart = nil
            }
        }
        if let start = intervalStart {
            result.append(DateInterval(start: start, end: range.end))
        }
        return result
    }
    
    public func transit(of planet: Planet, through houses: HouseRange, limit: TransitLimit) throws -> [DateInterval] {
        var range: DateInterval
        var maxCount: Int?
        switch limit {
        case .duration(let value):
            range = value
        case .count(let from, let count):
            maxCount = abs(count)
            // Average time it takes to complete `count` (for safety +1) number of revolutions in seconds
            let duration = Double(maxCount! + 1) * 360 * planet.avgSpeed * Calendar.Component.day.seconds
            range = count < 0 ? DateInterval(start: from.advanced(by: -duration), duration: duration) : DateInterval(start: from, duration: duration)
        }
        var result: [DateInterval]
        // Determine if it makes sense to parallelize
        let (count, unit) = planet.sampling(degrees: 30 * Double(houses.count))
        if range.duration / (Double(count) * unit.seconds) < 10000 {
            result = try transit(using: ephemeris, of: planet, through: houses, during: range)
        }
        else {
            result = try ephemeris.mapReduce(during: range, map: { (eph: IndicEphemeris, shard: DateInterval) throws -> [DateInterval] in
                try self.transit(using: eph, of: planet, through: houses, during: shard)
            }, reduce: { (shardResult: [DateInterval], previous: inout [DateInterval]?) -> Void in
                if previous == nil { previous = [] }
                if let last = previous!.popLast(), let next = shardResult.first, last.end == next.start {
                    previous!.append(last + next.duration)
                    previous!.append(contentsOf: shardResult[1...])
                }
                else {
                    previous!.append(contentsOf: shardResult)
                }
            })
        }
        return maxCount == nil ? result : Array(result[..<maxCount!])
    }
    
    public func lifetimeTransits(of planet: Planet, through houses: HouseRange) throws -> [DateInterval] {
        try transit(of: planet, through: houses, limit: .duration(DateInterval(start: ephemeris.dateUTC, duration: lifetimeInSeconds)))
    }
    
    public func nextTransit(of planet: Planet, through houses: HouseRange) throws -> DateInterval {
        let transits = try transit(of: planet, through: houses, limit: .count(from: Date(), count: 2))
        let today = Date()
        return transits.first() { !$0.contains(today) }!
    }
    
    public func lastTransit(of planet: Planet, through houses: HouseRange) throws -> DateInterval {
        let transits = try transit(of: planet, through: houses, limit: .count(from: Date(), count: -2))
        let today = Date()
        return transits.last() { !$0.contains(today) }!
    }
}
