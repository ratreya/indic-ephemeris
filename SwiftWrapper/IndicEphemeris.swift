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
 - Important: Since Swiss Ephemeris uses Thread Local Storage, you will see unexpected behavior if you pass an instance of this class between threads. For the same reason, this class does not call `swe_close()` in `deinit`. The consumers of this class should call `swe_close()` at the end of their thread lifecycle. Furthermore, the `Config` passed into a new instances of this class on a given thread will affect all previous instances created on the same thread. *Hence, it is advisible to only have one instance of this class per thread at any given time.*
 */
public class IndicEphemeris {
    let config: Config
    let dateUTC: Date
    let place: Place
    let log: Logger
    
    /**
     - Parameters:
        - date: time of birth at local timezone
        - at: `Place` of birth
     */
    public init(date: Date, at: Place, config userConfig: Config? = nil) {
        self.config = userConfig ?? Config()
        self.log = Logger(level: config.logLevel)
        self.place = at
        self.dateUTC = Calendar.current.date(byAdding: .second, value: -at.timezone.secondsFromGMT(for: date), to: date)!
        let path = (config.dataPath as NSString).utf8String
        swe_set_ephe_path(UnsafeMutablePointer<Int8>(mutating: path))
        swe_set_topo(at.longitude, at.latitude, at.altitude)
        swe_set_sid_mode(Int32(config.ayanamsha.rawValue), 0, 0)
    }
    
    internal func julianDay(for date: Date? = nil) throws -> Double {
        let components = Calendar.current.dateComponents(in: TimeZone.init(secondsFromGMT: 0)!, from: date ?? dateUTC)
        let times: UnsafeMutablePointer<Double> = UnsafeMutablePointer.allocate(capacity: 2)
        let error = UnsafeMutablePointer<Int8>.allocate(capacity: 256)
        defer {
            times.deallocate()
            error.deallocate()
        }
        if swe_utc_to_jd(Int32(components.year!), Int32(components.month!), Int32(components.day!), Int32(components.hour!), Int32(components.minute!), Double(components.second!), SE_GREG_CAL, times, error) < 0 {
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
            if swe_calc_ut(try julianDay(for: date), Int32(ordinal), SEFLG_SWIEPH | SEFLG_TOPOCTR | SEFLG_SIDEREAL | SEFLG_SPEED, positions, error) < 0 {
                throw EphemerisError.runtimeError(String(cString: error))
            }
            let message = String(cString: error)
            if !message.isEmpty {
                log.warning(message)
            }
            if planet == .SouthNode {
                result.append((date, Position(logitude: (positions[0] + 180).truncatingRemainder(dividingBy: 360), latitude: -positions[1], distance: positions[2], speed: -positions[3])))
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
            if swe_pheno_ut(try julianDay(for: date), Int32(planet.rawValue), SEFLG_TOPOCTR, response, error) < 0 {
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
    
    public func ascendant() throws -> Position {
        let cusps: UnsafeMutablePointer<Double> = UnsafeMutablePointer.allocate(capacity: 13)
        let ascmc: UnsafeMutablePointer<Double> = UnsafeMutablePointer.allocate(capacity: 10)
        defer {
            cusps.deallocate()
            ascmc.deallocate()
        }
        if swe_houses_ex(try julianDay(), SEFLG_SIDEREAL, place.latitude, place.longitude, Int32(Character("W").asciiValue!), cusps, ascmc) < 0 {
            throw EphemerisError.runtimeError("swe_houses_ex returned error for unknown reasons")
        }
        return Position(logitude: ascmc[0])
    }
}
