/*
* IndicEphemeris is a fluent Swift interface to Swiss Ephemeris with Indic Astrology specific extensions.
* Copyright (C) 2020 Ranganath Atreya
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
*/

import Foundation

/**
 Encapsulation of logic to either run on a fixed thread or on the caller thread. Swiss Ephemeris uses thread-local store and so, the only way to encapsulate state is to run all swe_* functions on the same thread.
 - Important: `ThreadExecutor` itself is not thread-safe. But within a single thread it is reentrant.
 */
fileprivate final class ThreadExecutor: NSObject {
    private var useCaller: Bool
    private var work: () -> Void = {}
    private var thread: Thread?
    private var start: DispatchSemaphore?
    private var end: DispatchSemaphore?
    
    fileprivate init(_ useCaller: Bool) {
        self.useCaller = useCaller
        super.init()
        if !useCaller {
            start = DispatchSemaphore(value: 0)
            end = DispatchSemaphore(value: 0)
            thread = Thread(target: self, selector: #selector(self.threadMain), object: nil)
            thread!.name = UUID().uuidString
            thread!.start()
        }
    }

    @objc fileprivate func threadMain() {
        while true {
            start!.wait()
            if thread!.isCancelled { break }
            work()
            end!.signal()
        }
    }
    
    deinit {
        thread?.cancel()
        start?.signal()
    }

    fileprivate func execute(action: @escaping () -> Void) {
        // Make a single thread reentrant but deadlocks can still happen between different threads
        if useCaller || Thread.current.name == thread!.name {
            action()
            return
        }
        /// Access to `work` is not synchronized as the whole class is not guaranteed to be thread-safe
        work = action
        start!.signal()
        end!.wait()
    }
}

public class IndicEphemeris {
    private let queue: DispatchQueue
    private let executor: ThreadExecutor
    let config: Config
    let dateUTC: Date
    let place: Place
    let log: Logger
    
    /**
     - Parameters:
        - date: time of birth at local timezone.
        - at: `Place` of birth.
        - config: (optional) configuration to use. If omitted, then default configuration is used.
        - useCaller: (optional) defailt is to use a separate thread to encapsulate internal state.
     - Note: if `useCaller` is `true` then the internal state of Swiss Ephemeris is shared for all instances created on the caller thread. If `false`, then each instance fully encapsulates its internal state.
     */
    public init(date: Date, at: Place, config userConfig: Config? = nil, useCaller: Bool = false) {
        config = userConfig ?? Config()
        log = Logger(level: config.logLevel)
        place = at
        dateUTC = Calendar.current.date(byAdding: .second, value: -at.timezone.secondsFromGMT(for: date), to: date)!
        queue = DispatchQueue(label: "com.daivajnanam.IndicEphemeris", qos: .userInitiated, attributes: .concurrent, autoreleaseFrequency: .workItem)
        executor = ThreadExecutor(useCaller)
        executor.execute {
            let path = (self.config.dataPath as NSString).utf8String
            swe_set_ephe_path(UnsafeMutablePointer<Int8>(mutating: path))
            swe_set_topo(at.longitude, at.latitude, at.altitude)
            swe_set_sid_mode(Int32(self.config.ayanamsha.rawValue), 0, 0)
        }
    }
    
    deinit {
        executor.execute {
            swe_close()
        }
    }
    
    internal func julianDay(for date: Date? = nil) throws -> Double {
        // Swiss Ephemeris uses proliptic Gregorian calendar while Swift on OS X does not.
        var calendarType = SE_GREG_CAL
        let target = date ?? dateUTC
        #if os(macOS)
        if target < Date(timeIntervalSince1970: -12219292800.0) { // 1582-10-15T00:00:00+0000
            calendarType = SE_JUL_CAL
        }
        #endif
        let components = Calendar.current.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: target)
        let times: UnsafeMutablePointer<Double> = UnsafeMutablePointer.allocate(capacity: 2)
        let error = UnsafeMutablePointer<Int8>.allocate(capacity: 256)
        defer {
            times.deallocate()
            error.deallocate()
        }
        var retval: Int32 = 0
        executor.execute {
            retval = swe_utc_to_jd(Int32(components.year!), Int32(components.month!), Int32(components.day!), Int32(components.hour!), Int32(components.minute!), Double(components.second!), calendarType, times, error)
        }
        if retval < 0 {
            throw EphemerisError.runtimeError(String(cString: error))
        }
        let message = String(cString: error)
        if !message.isEmpty {
            log.warning(message)
        }
        return times[1]
    }
    
    func dates(during range: DateInterval, every delta: Int, unit: Calendar.Component) throws -> [Date] {
        var dates = [Date]()
        var date = range.start
        while date < range.end {
            dates.append(date)
            guard let next = Calendar.current.date(byAdding: unit, value: delta, to: date) else { break }
            date = next
        }
        return dates
    }
    
    public func positions(for planet: Planet, at dates: [Date]) throws -> [(Date, Position)] {
        let positions: UnsafeMutablePointer<Double> = UnsafeMutablePointer.allocate(capacity: 6)
        let error = UnsafeMutablePointer<Int8>.allocate(capacity: 256)
        defer {
            positions.deallocate()
            error.deallocate()
        }
        var result = [(Date, Position)]()
        for date in dates {
            // For South Node, get North Node position and invert it
            let ordinal = planet == .SouthNode ? Planet.NorthNode.rawValue : planet.rawValue
            var retval: Int32 = 0
            executor.execute {
                retval = swe_calc_ut(try! self.julianDay(for: date), Int32(ordinal), SEFLG_SWIEPH | SEFLG_TOPOCTR | SEFLG_SIDEREAL | SEFLG_SPEED, positions, error)
            }
            if retval < 0 {
                throw EphemerisError.runtimeError(String(cString: error))
            }
            let message = String(cString: error)
            if !message.isEmpty {
                log.warning(message)
            }
            if planet == .SouthNode {
                result.append((date, Position(logitude: (positions[0] + 180).truncatingRemainder(dividingBy: 360), latitude: -positions[1], distance: positions[2], speed: positions[3])))
            }
            else {
                result.append((date, Position(logitude: positions[0], latitude: positions[1], distance: positions[2], speed: positions[3])))
            }
        }
        return result
    }
    
    public func position(for planet: Planet) throws -> Position {
        return try positions(for: planet, at: [dateUTC]).first!.1
    }

    public func positions(for planet: Planet, during range: DateInterval, every time: TimeInterval) throws -> [(Date, Position)] {
        let dates = stride(from: range.start.timeIntervalSince1970, to: range.end.timeIntervalSince1970, by: time).map({ Date(timeIntervalSince1970: $0) })
        return try positions(for: planet, at: dates)
    }

    public func positions(for planet: Planet, during range: DateInterval, every delta: Int, unit: Calendar.Component) throws -> [(Date, Position)] {
        return try positions(for: planet, at: dates(during: range, every: delta, unit: unit))
    }

    public func phases(for planet: Planet, at dates: [Date]) throws -> [(Date, Phase)] {
        let response: UnsafeMutablePointer<Double> = UnsafeMutablePointer.allocate(capacity: 20)
        let error = UnsafeMutablePointer<Int8>.allocate(capacity: 256)
        defer {
            response.deallocate()
            error.deallocate()
        }
        var result = [(Date, Phase)]()
        for date in dates {
            var retval: Int32 = 0
            executor.execute {
                retval = swe_pheno_ut(try! self.julianDay(for: date), Int32(planet.rawValue), SEFLG_TOPOCTR, response, error)
            }
            if retval < 0 {
                throw EphemerisError.runtimeError(String(cString: error))
            }
            let message = String(cString: error)
            if !message.isEmpty {
                log.warning(message)
            }
            result.append((date, Phase(angle: response[0], illunation: response[1], elongation: response[2], diameter: response[3], magnitude: response[4])))
        }
        return result
    }
    
    public func phase(for planet: Planet) throws -> Phase {
        return try phases(for: planet, at: [dateUTC]).first!.1
    }
    
    public func phases(for planet: Planet, during range: DateInterval, every delta: Int, unit: Calendar.Component) throws -> [(Date, Phase)] {
        return try phases(for: planet, at: dates(during: range, every: delta, unit: unit))
    }
    
    func houses() throws -> (cusps: [Double], ascmc: [Double]) {
        let cusps: UnsafeMutablePointer<Double> = UnsafeMutablePointer.allocate(capacity: 13)
        let ascmc: UnsafeMutablePointer<Double> = UnsafeMutablePointer.allocate(capacity: 10)
        defer {
            cusps.deallocate()
            ascmc.deallocate()
        }
        var retval: Int32 = 0
        executor.execute {
            retval = swe_houses_ex(try! self.julianDay(for: self.dateUTC), SEFLG_SIDEREAL, self.place.latitude, self.place.longitude, Int32(Character("W").asciiValue!), cusps, ascmc)
        }
        if retval < 0 {
            throw EphemerisError.runtimeError("swe_houses_ex returned error for unknown reasons")
        }
        return (Array(UnsafeBufferPointer(start: cusps, count: 13)), Array(UnsafeBufferPointer(start: ascmc, count: 10)))
    }
    
    public func ascendant() throws -> Position {
        return Position(logitude: try houses().ascmc[0])
    }

    private enum AsycResult<T> {
        case result([T])
        case error(Error)
    }

    /**
     If you need to do run many ephemeris calculations over a large period of time, this function provides the boilerplate code for running them in parallel.
     Function takes a date `range`, shards the date range into `Config.concurrency` number of shards, executes the `map` function on these shards in parallel and serially calls `reduce` with results from `map` in chronological order.
     - Parameters:
        - during: `DateInterval` to shard and over which to run `map`.
        - map: Closure that takes an instance of `IndicEphemeris` and a shard of `DateInterval`, performs some operation and returns an array of results.
        - reduce: Closure that takes one result at a time from `map` in chronological order along with the result from the previous run of `reduce` and returns new results. The first call to `reduce` will send in `nil` as previous result.
     - Returns: The final result from the last call to `reduce`
     - Throws: Any exception that may be thrown from any run of `map`.
     */
    public func mapReduce<T, W>(during range: DateInterval, map: @escaping (IndicEphemeris, DateInterval) throws -> [T], reduce: ([T], inout W?) -> Void) throws -> W {
        // Map
        let shardDuration = range.duration / Double(config.concurrency)
        let shards = Array(0..<config.concurrency).map { shard in  DateInterval(start: range.start.advanced(by: shardDuration * Double(shard)), duration: shardDuration) }
        let mutex = DispatchSemaphore(value: 1)
        var shardResults = [Int: AsycResult<T>]()
        let group = DispatchGroup()
        for index in 0..<config.concurrency {
            group.enter()
            queue.async(group: group) {
                let eph = IndicEphemeris(date: self.dateUTC, at: self.place, config: self.config, useCaller: true)
                var shardResult: AsycResult<T>
                do {
                    shardResult = .result(try map(eph, shards[index]))
                }
                catch let exp {
                    shardResult = .error(exp)
                }
                mutex.wait()
                shardResults[index] = shardResult
                mutex.signal()
                group.leave()
            }
        }
        group.wait()
        // Reduce
        var result: W?
        for index in shardResults.keys.sorted() {
            let shardResult = shardResults[index]!
            switch shardResult {
            case .error(let exp):
                throw exp
            case .result(let shardResult):
                reduce(shardResult, &result)
            }
        }
        return result!
    }
}
