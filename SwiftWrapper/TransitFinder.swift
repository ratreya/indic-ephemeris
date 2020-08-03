/*
* IndicEphemeris is a fluent Swift interface to Swiss Ephemeris with Indic Astrology specific extensions.
* Copyright (C) 2020 Ranganath Atreya
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
*/

import Foundation

extension House {
    public var degrees: DegreeRange {
        return DegreeRange(lowerBound: Double(self.rawValue * 30), size: 30)
    }
}

public struct HouseRange: CustomStringConvertible {
    let lowerBound: House
    let count: Int
    let constituent: Set<House>
    
    public var description: String { constituent.description }
    public var degrees: DegreeRange { DegreeRange(lowerBound: lowerBound.degrees.lowerBound, size: Double(count * 30)) }

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

public struct DegreeRange: CustomStringConvertible {
    let lowerBound: Double
    let size: Double
    let upperBound: Double
    
    public var description: String { "[\(lowerBound), \(upperBound))" }

    public init(lowerBound: Double, size: Double) {
        self.lowerBound = lowerBound
        self.size = size
        upperBound = (lowerBound + size).truncatingRemainder(dividingBy: 360)
    }
    
    public func contains(_ degree: Double) -> Bool {
        if lowerBound < upperBound { return (lowerBound <= degree) && (degree < upperBound) }
        else { return (degree >= lowerBound) || (degree < upperBound) }
    }
    
    public func inverted() -> DegreeRange { DegreeRange(lowerBound: upperBound, size: 360 - size) }
}

public enum TransitLimit {
    case count(from: Date, count: Int)
    case duration(DateInterval)
}

let granularityOrder: [Calendar.Component] = [.year, .month, .day, .hour, .minute, .second]

extension Calendar.Component {
    var seconds: TimeInterval {
        Calendar.current.date(byAdding: self, value: 1, to: Date(timeIntervalSince1970: 0))!.timeIntervalSince1970
    }
    func isFiner(than unit: Calendar.Component) -> Bool { self.seconds < unit.seconds }
    var nextFiner: Calendar.Component? { self == .second ? nil : granularityOrder[granularityOrder.firstIndex(of: self)!.advanced(by: 1)] }
    func isCoarser(than unit: Calendar.Component) -> Bool { self.seconds > unit.seconds }
    var nextCoarser: Calendar.Component? { self == .year ? nil : granularityOrder[granularityOrder.firstIndex(of: self)!.advanced(by: -1)] }
}

extension DateInterval {
    static func + (right: DateInterval, left: TimeInterval) -> DateInterval {
        DateInterval(start: right.start, duration: right.duration + left)
    }
    func startExpanded(by duration: TimeInterval) -> DateInterval { DateInterval(start: start.advanced(by: -duration), end: end) }
    func endExpanded(by duration: TimeInterval) -> DateInterval { DateInterval(start: start, end: end.advanced(by: duration)) }
    func beforeStart(duration: TimeInterval) -> DateInterval { DateInterval(start: start.advanced(by: -duration), duration: duration) }
    func fromStart(duration: TimeInterval) -> DateInterval { DateInterval(start: start, duration: duration) }
    func beforeEnd(duration: TimeInterval) -> DateInterval { DateInterval(start: end.advanced(by: -duration), duration: duration) }
    func fromEnd(duration: TimeInterval) -> DateInterval { DateInterval(start: end, duration: duration) }
}

extension TimeInterval {
    var granularity: (value: Int, unit: Calendar.Component) {
        for i in stride(from: granularityOrder.count-1, to: 0, by: -1) {
            if (granularityOrder[i].seconds..<granularityOrder[i-1].seconds).contains(self) {
                return (Int(self/granularityOrder[i].seconds), granularityOrder[i])
            }
        }
        return (Int(self/granularityOrder[0].seconds), granularityOrder[0])
    }
}

extension Planet {
    /**
     Minimum time in seconds required to travel specified number of degrees.
     */
    func minTime(for degrees: Double) -> TimeInterval {
        abs(degrees/self.maxSpeed * Calendar.Component.day.seconds)
    }

    /**
     Average time in seconds required to travel specified number of degrees.
     */
    func avgTime(for degrees: Double) -> TimeInterval {
        abs(degrees/self.avgSpeed * Calendar.Component.day.seconds)
    }

    /**
     Average number of degrees traveled in specified time.
     */
    func avgDegrees(for time: TimeInterval) -> Double {
        abs(time * self.avgSpeed / Calendar.Component.day.seconds)
    }
    
    /**
     Maximum number of degrees traveled in specified time.
     */
    func maxDegrees(for time: TimeInterval) -> Double {
        abs(time * self.maxSpeed / Calendar.Component.day.seconds)
    }
}

public class TransitFinder {
    private let ephemeris: IndicEphemeris
    private let intervalStitcher = { (shardResult: [DateInterval], previous: inout [DateInterval]?) -> Void in
        if previous == nil { previous = [] }
        if let last = previous!.popLast(), let next = shardResult.first, last.end == next.start {
            previous!.append(last + next.duration)
            previous!.append(contentsOf: shardResult[1...])
        }
        else {
            previous!.append(contentsOf: shardResult)
        }
    }

    public init(_ ephemeris: IndicEphemeris) {
        self.ephemeris = ephemeris
    }
    
    func refineEdge(using eph: IndicEphemeris, satisfying predicate: (Position) throws -> Bool, during range: DateInterval, for planet: Planet, resolution upto: Calendar.Component? = nil) throws -> Date? {
        let (inputValue, inputUnit) = range.duration.granularity
        let desiredUnit = upto ?? ephemeris.config.transitResolution
        if inputUnit.isFiner(than: desiredUnit) || (inputUnit == desiredUnit && inputValue == 1) {
            return try eph.positions(for: planet, at: [range.start, range.end]).filter { try predicate($0.1) }.first?.0
        }
        let next = inputUnit.isCoarser(than: desiredUnit) ? inputUnit.nextFiner! : inputUnit
        let timePositions = try eph.positions(for: planet, during: range + inputUnit.seconds, every: 1, unit: next)
        if let index = try timePositions.firstIndex(where: { try predicate($0.1) }) {
            if index == 0 { return timePositions[index].0 }
            return try refineEdge(using: eph, satisfying: predicate, during: DateInterval(start: timePositions[index - 1].0, end: timePositions[index].0), for: planet)
        }
        return nil
    }
    
    func intervals(using eph: IndicEphemeris, for planet: Planet, in timePositions: [(Date, Position)], satisfying predicate: (Position) throws -> Bool, resolution upto: Calendar.Component? = nil) throws -> [DateInterval] {
        var result = [DateInterval]()
        var intervalStart: Date? = nil
        for index in timePositions.indices {
            let (time, position) = timePositions[index]
            if try predicate(position), intervalStart == nil {
                intervalStart = index == 0 ? time : try refineEdge(using: eph, satisfying: predicate, during: DateInterval(start: timePositions[index-1].0, end: time), for: planet, resolution: upto)!
            }
            if let start = intervalStart, try !predicate(position) {
                let refined = try refineEdge(using: eph, satisfying: { try !predicate($0) }, during: DateInterval(start: timePositions[index-1].0, end: time), for: planet, resolution: upto)!
                result.append(DateInterval(start: start, end: refined))
                intervalStart = nil
            }
        }
        if let start = intervalStart {
            result.append(DateInterval(start: start, end: timePositions.last!.0))
        }
        return result
    }
    
    func transits(using eph: IndicEphemeris, for planet: Planet, satisfying predicate: (Position) throws -> Bool, during interval: DateInterval, sampling time: TimeInterval, resolution upto: Calendar.Component? = nil) throws -> [DateInterval] {
        let timePositions = try eph.positions(for: planet, during: interval, every: time)
        return try intervals(using: eph, for: planet, in: timePositions, satisfying: predicate, resolution: upto)
    }

    /*
     Incorrect ommissions and inclusions can happen due to retrogradation at the edges.The speed at various positions in that case will be as follows.
     This is the path of a planet unrolled over time:
     
                     2R                                                        2R
              |<------------>|                                          |<------------>|
     .........|====|.........|====================//====================|.........|====|.........
             --->|<--->|<--->|                                          |<--->|<--->|<---
             +ve   -ve   +ve                                              +ve   -ve   +ve
           ^     ^     ^          ^                                ^          ^     ^     ^  -- force samples at these locations
           1     2     3          4                                5          6     7     8
     
     The -ve part is the time in retrograde. The sum of incorrect inclusion and pre-retrograde transit is always 2 * R (max retrograde time).
     */
    
    /**
     Sampling logic used to find transits can have incorrect ommisions or inclusions of time intervals near edges due to retrograde motion of planets. This function fixes those inaccuracies.
     */
    func fixEdges(of ranges: [DateInterval], for planet: Planet, through degrees: DegreeRange) throws -> [DateInterval] {
        if planet.retrograde == 0 { return ranges }
        // The idea is to force samples at locations such that all potential edges will be detected.
        // For this to work, the interval between transits per revolution must be greater than 2*R on both sides.
        if planet.maxDegrees(for: 4 * planet.retrograde) > 360 - degrees.size + 6 { // +6 for safety
            ephemeris.log.warning("There isen't enough space to fixEdges for \(planet) through \(degrees) in \(ranges).")
            return ranges
        }
        var result = [DateInterval]()
        for transit in ranges {
            var samples = [Date]()
            // Leading edge
            if let retro = try retrogrades(of: planet, overlapping: transit.beforeStart(duration: 2 * planet.retrograde)).first { // Incorrect exlusion case
                samples.append(transit.start.advanced(by: (-2 * planet.retrograde) - Calendar.Component.day.seconds)) // 1: one day for safety
                samples.append(contentsOf: [retro.start, retro.end]) // 2, 3
                samples.append(transit.start.advanced(by: transit.duration/4)) // 4
            }
            if let retro = try retrogrades(of: planet, overlapping: transit.fromStart(duration: 2 * planet.retrograde)).first { // Incorrect inclusion case
                samples.append(transit.start) // 1
                samples.append(contentsOf: [retro.start, retro.end]) // 2, 3
                samples.append(transit.start.advanced(by: (2 * planet.retrograde) + Calendar.Component.day.seconds)) // 4
            }
            samples.append(transit.start)
            // Traling edge
            if let retro = try retrogrades(of: planet, overlapping: transit.beforeEnd(duration: 2 * planet.retrograde)).first { // Incorrect inlusion case
                samples.append(transit.end.advanced(by: (-2 * planet.retrograde) - Calendar.Component.day.seconds)) // 5: one day for safety
                samples.append(contentsOf: [retro.start, retro.end]) // 6, 7
                samples.append(transit.end) // 8
            }
            if let retro = try retrogrades(of: planet, overlapping: transit.fromEnd(duration: 2 * planet.retrograde)).first { // Incorrect exclusion case
                samples.append(transit.end.advanced(by: 3600))  // 5: one day for safety
                samples.append(contentsOf: [retro.start, retro.end])    // 6, 7
                samples.append(transit.end.advanced(by: (2 * planet.retrograde) + Calendar.Component.day.seconds)) // 8
            }
            samples.append(transit.end)
            if samples.count == 2 {
                result.append(transit)
            }
            else {
                // We don't have to worry about samples of one transit overflowing into the next because the next transit is a whole revolution away
                let timePositions = try ephemeris.positions(for: planet, at: samples.sorted())
                result.append(contentsOf: try intervals(using: ephemeris, for: planet, in: timePositions, satisfying: { degrees.contains($0.longitude) }))
            }
        }
        return result
    }
    
    public func retrogrades(of planet: Planet, overlapping range: DateInterval) throws -> [DateInterval] {
        if planet.retrograde == 0 { return [] }
        let predicate: (Position) throws -> Bool = (planet == .NorthNode || planet == .SouthNode) ? { $0.speed! > 0 } : { $0.speed! < 0 }
        // Expand the interval if the planet is retrograde at the edges
        var interval = range
        let edgeTimePositions = try ephemeris.positions(for: planet, at: [interval.start, interval.end])
        if try predicate(edgeTimePositions[0].1) {
            interval = interval.startExpanded(by: planet.retrograde)
        }
        if try predicate(edgeTimePositions[1].1) {
            interval = interval.endExpanded(by: planet.retrograde)
        }
        // All planets have a peculiar retrograde motion where it sometimes briefly reverses course at the fringes of its retrograde period
        // Length of fringe is proportional to synodic period - we do an equivalent of 2 days for Saturn
        let maxFringePeriod: Double = (2/378)*planet.synodicPeriod
        let computation = { (eph: IndicEphemeris, shard: DateInterval) throws -> [DateInterval] in
            let retros = try self.transits(using: eph, for: planet, satisfying: predicate, during: interval, sampling: planet.retrograde/2, resolution: .day)
            var samples = [(Date, Position)]()
            for retro in retros {
                if retro.duration < planet.retrograde/2 { // This is a fringe and will be caught by the main retrogration
                    self.ephemeris.log.debug("Ignoring fringe retorgrade period \(retro)")
                    continue
                }
                samples.append(contentsOf: try eph.positions(for: planet, during: retro.beforeStart(duration: maxFringePeriod), every: 1, unit: .hour))
                samples.append(contentsOf: try eph.positions(for: planet, during: retro.fromStart(duration: maxFringePeriod), every: 1, unit: .hour))
                samples.append(contentsOf: try eph.positions(for: planet, during: retro.beforeEnd(duration: maxFringePeriod), every: 1, unit: .hour))
                samples.append(contentsOf: try eph.positions(for: planet, during: retro.fromEnd(duration: maxFringePeriod), every: 1, unit: .hour))
            }
            let intervals = try self.intervals(using: eph, for: planet, in: samples, satisfying: predicate)
            switch self.ephemeris.config.retrogradeDefinition {
            case .strict:
                return intervals
            case .largest, .maximal:
                let policy = { (fragments: [DateInterval]) -> DateInterval in
                    switch self.ephemeris.config.retrogradeDefinition {
                    case .largest:
                        return fragments.max(by: { $0.duration < $1.duration })!
                    case .maximal:
                        return DateInterval(start: fragments.first!.start, end: fragments.last!.end)
                    default:
                        fatalError()
                    }
                }
                var results = [DateInterval]()
                var fragments = [DateInterval]()
                for interval in intervals {
                    if let last = fragments.last, (interval.start.timeIntervalSince1970 - last.end.timeIntervalSince1970) > maxFringePeriod {
                        results.append(policy(fragments))
                        fragments.removeAll()
                    }
                    else {
                        fragments.append(interval)
                    }
                }
                if !fragments.isEmpty { results.append(policy(fragments)) }
                return results
            }
        }
        // Now execute the computation concurrently or not depending on number of initial samples
        if interval.duration / (planet.retrograde/2) < Double(ephemeris.config.concurrencyThreshold) {
            return try computation(ephemeris, interval)
        }
        else {
            return try ephemeris.mapReduce(during: interval, map: { (eph: IndicEphemeris, shard: DateInterval) throws -> [DateInterval] in
                try computation(eph, shard)
            }, reduce: intervalStitcher)
        }
    }
    
    public func transits(of planet: Planet, through degrees: DegreeRange, limit upto: TransitLimit) throws -> [DateInterval] {
        var range: DateInterval
        var maxCount: Int?
        switch upto {
        case .duration(let value):
            range = value
        case .count(let from, let count):
            maxCount = abs(count)
            // Average time it takes to complete `count` (+1, for safety) number of revolutions in seconds
            let duration = planet.avgTime(for: Double(maxCount! + 1) * 360)
            range = count < 0 ? DateInterval(start: from.advanced(by: -duration), duration: duration) : DateInterval(start: from, duration: duration)
        }
        var result: [DateInterval]
        // Determine if it makes sense to parallelize
        let sampling = planet.minTime(for: degrees.size)
        if range.duration / sampling < Double(ephemeris.config.concurrencyThreshold) {
            result = try transits(using: ephemeris, for: planet, satisfying: { degrees.contains($0.longitude) }, during: range, sampling: sampling)
        }
        else {
            result = try ephemeris.mapReduce(during: range, map: { (eph: IndicEphemeris, shard: DateInterval) throws -> [DateInterval] in
                try self.transits(using: eph, for: planet, satisfying: { degrees.contains($0.longitude) }, during: range, sampling: sampling)
            }, reduce: intervalStitcher)
        }
        result = try fixEdges(of: result, for: planet, through: degrees)
        return maxCount == nil ? result : Array(result[..<maxCount!])
    }
    
    public func transits(of planet: Planet, through houses: HouseRange, limit upto: TransitLimit) throws -> [DateInterval] {
        return try transits(of: planet, through: houses.degrees, limit: upto)
    }
    
    public func lifetimeTransits(of planet: Planet, through houses: HouseRange) throws -> [DateInterval] {
        try transits(of: planet, through: houses, limit: .duration(DateInterval(start: ephemeris.dateUTC, duration: lifetimeInSeconds)))
    }
    
    public func nextTransit(of planet: Planet, through houses: HouseRange) throws -> DateInterval {
        let ranges = try transits(of: planet, through: houses, limit: .count(from: Date(), count: 2))
        let today = Date()
        return ranges.first() { !$0.contains(today) }!
    }
    
    public func previousTransit(of planet: Planet, through houses: HouseRange) throws -> DateInterval {
        let ranges = try transits(of: planet, through: houses, limit: .count(from: Date(), count: -2))
        let today = Date()
        return ranges.last() { !$0.contains(today) }!
    }
}
