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

public class TransitFinder {
    private let ephemeris: IndicEphemeris
    private let queue: DispatchQueue

    public init(_ ephemeris: IndicEphemeris) {
        self.ephemeris = ephemeris
        self.queue = DispatchQueue(label: "com.daivajnanam.IndicEphemeris.TransitFinder", qos: .userInitiated, attributes: .concurrent, autoreleaseFrequency: .workItem)
    }
    
    public enum TransitLimit {
        case count(Date, Int)
        case duration(DateInterval)
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
        let timePositions = try ephemeris.positions(for: planet, during: range, every: houses.count, unit: planet.sampling)
        var result = [DateInterval]()
        var intervalStart: Date? = nil
        for index in timePositions.indices {
            let (time, position) = timePositions[index]
            let currentHouse = try position.houseLocation().house
            if houses.contains(currentHouse), intervalStart == nil {
                intervalStart = index == 0 ? time : try refineEdge(using: ephemeris, transit: houses, in: DateInterval(start: timePositions[index-1].0, end: time.advanced(by: 1)), for: planet, from: planet.sampling)!
            }
            if let start = intervalStart, !houses.contains(currentHouse) {
                let refined = try refineEdge(using: ephemeris, transit: houses.inverted(), in: DateInterval(start: timePositions[index-1].0, end: time.advanced(by: 1)), for: planet, from: planet.sampling)!
                result.append(DateInterval(start: start, end: refined))
                intervalStart = nil
            }
        }
        if let start = intervalStart {
            result.append(DateInterval(start: start, end: range.end))
        }
        return result
    }
    
    private enum AsycResult {
        case result([DateInterval])
        case error(Error)
    }
    
    public func transit(of planet: Planet, through houses: HouseRange, limit: TransitLimit) throws -> [DateInterval] {
        var range: DateInterval
        var maxCount: Int?
        switch limit {
        case .duration(let value):
            range = value
        case .count(let from, let count):
            // Max time it takes the planet to complete a full rotation
            if count <= 0 { throw EphemerisError.runtimeError("Count has to be greater than 0") }
            maxCount = count
            range = DateInterval(start: from, duration: Double(count) * 12 * planet.sampling.seconds)
        }
        var result: [DateInterval]
        // Determine if it makes sense to parallelize
        if range.duration / (planet.sampling.seconds * Double(houses.count)) < 10000 {
            result = try transit(using: ephemeris, of: planet, through: houses, during: range)
        }
        else {
            let shardDuration = range.duration / Double(ephemeris.config.transitConcurrency)
            let shards = Array(0..<ephemeris.config.transitConcurrency).map { shard in  DateInterval(start: range.start.advanced(by: shardDuration * Double(shard)), duration: shardDuration) }
            var shardResults = [Int: AsycResult]()
            let group = DispatchGroup()
            for index in 0..<ephemeris.config.transitConcurrency {
                group.enter()
                queue.async {
                    let eph = IndicEphemeris(date: self.ephemeris.dateUTC, at: self.ephemeris.place, config: self.ephemeris.config)
                    var shardResult: AsycResult
                    do {
                        shardResult = .result(try self.transit(using: eph, of: planet, through: houses, during: shards[index]))
                    }
                    catch let exp {
                        shardResult = .error(exp)
                    }
                    self.queue.async(flags: .barrier) {
                        shardResults[index] = shardResult
                    }
                    group.leave()
                }
            }
            group.wait()
            // Stitch shard results together
            result = []
            for index in shardResults.keys.sorted() {
                let shardResult = shardResults[index]!
                switch shardResult {
                case .error(let exp):
                    throw exp
                case .result(let shardResult):
                    if let last = result.popLast(), let next = shardResult.first, last.end == next.start {
                        result.append(last + next.duration)
                        result.append(contentsOf: shardResult[1...])
                    }
                    else {
                        result.append(contentsOf: shardResult)
                    }
                }
            }
        }
        return maxCount == nil ? result : Array(result[..<maxCount!])
    }
    
    public func allTransits(of planet: Planet, through houses: HouseRange) throws -> [DateInterval] {
        return try transit(of: planet, through: houses, limit: .duration(DateInterval(start: ephemeris.dateUTC, duration: lifetimeInSeconds)))
    }
    
    public func nextTransit(of planet: Planet, through houses: HouseRange) throws -> [DateInterval] {
        return try transit(of: planet, through: houses, limit: .count(Date(), 1))
    }
}
