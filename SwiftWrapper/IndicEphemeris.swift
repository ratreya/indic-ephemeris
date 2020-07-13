//
//  Ephemeris.swift
//  swift-ephemeris
//
//  Created by Atreya Ranganath on 7/7/20.
//  Copyright © 2020 Daivajnanam. All rights reserved.
//

import Foundation

public class IndicEphemeris {
    private let dateUTC: Date
    private let place: Place
    
    /**
     - Parameters:
        - date: time of birth at local timezone
        - at: `Place` of birth
        - ayanamsha: optional `Ayanamsha` defaulting to Lahiri
     */
    public init(date: Date, at: Place, ayanamsha: Ayanamsha = .Lahiri) {
        self.place = at
        self.dateUTC = Calendar.current.date(byAdding: .second, value: -at.timezone.secondsFromGMT(for: date), to: date)!
        let path = (Bundle(for: IndicEphemeris.self).bundleURL.appendingPathComponent("Resources", isDirectory: true).appendingPathComponent("EphemerisData", isDirectory: true).path as NSString).utf8String
        swe_set_ephe_path(UnsafeMutablePointer<Int8>(mutating: path))
        swe_set_topo(at.longitude, at.latitude, at.altitude)
        swe_set_sid_mode(Int32(ayanamsha.rawValue), 0, 0)
    }
    
    deinit {
        swe_close()
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
            Logger.log.warning(message)
        }
        return times[1]
    }
    
    internal func dates(during range: DateInterval, every delta: Int, unit: Calendar.Component) throws -> [Date] {
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
            if swe_calc_ut(try julianDay(), Int32(planet.rawValue), SEFLG_SWIEPH | SEFLG_TOPOCTR | SEFLG_SIDEREAL | SEFLG_SPEED, positions, error) < 0 {
                throw EphemerisError.runtimeError(String(cString: error))
            }
            let message = String(cString: error)
            if !message.isEmpty {
                Logger.log.warning(message)
            }
            result.append((date, Position(logitude: positions[0], latitude: positions[1], distance: positions[2], speed: positions[3])))
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
            if swe_pheno_ut(try julianDay(), Int32(planet.rawValue), SEFLG_TOPOCTR, response, error) < 0 {
                throw EphemerisError.runtimeError(String(cString: error))
            }
            let message = String(cString: error)
            if !message.isEmpty {
                Logger.log.warning(message)
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
        swe_houses_ex(try julianDay(), SEFLG_SIDEREAL, place.latitude, place.longitude, Int32(Character("W").asciiValue!), cusps, ascmc)
        return Position(logitude: ascmc[0])
    }

    static let dashaOrder: [Planet] = [.SouthNode, .Venus, .Sun, .Moon, .Mars, .NorthNode, .Jupiter, .Saturn, .Mercury]
    internal enum DashaStart {
        case MahaDasha(planet: Planet)
        case Moon(position: Position)
    }
    
    internal func dashas(for interval: DateInterval, starting from: DashaStart) -> [(DateInterval, Planet)] {
        var first: (DateInterval, Planet)
        switch from {
        case .MahaDasha(let planet):
            first = (DateInterval(start: interval.start, duration: Double(planet.dashaPeriod)/120.0 * interval.duration), planet)
        case .Moon(let position):
            let natal = position.nakshatraLocation()
            let secondsElapsed = natal.degrees*60*60 + natal.minutes*60 + natal.seconds
            let total = Double(natal.nakshatra.ruler.dashaPeriod)/120.0 * interval.duration
            let remaining = (48000.0 - Double(secondsElapsed))/48000.0 * total  // 48,000 seconds per nakshatra
            first = (DateInterval(start: interval.start, duration: remaining), natal.nakshatra.ruler) // 31,536,000 seconds in one year
        }
        var result = [(DateInterval, Planet)]()
        result.append(first)
        var index = IndicEphemeris.dashaOrder.firstIndex(of: first.1)!
        var date = first.0.end
        while date < interval.end {
            index = (index + 1) % IndicEphemeris.dashaOrder.count
            let planet = IndicEphemeris.dashaOrder[index]
            let next = (DateInterval(start: interval.start, duration: Double(planet.dashaPeriod)/120.0 * interval.duration), planet)
            result.append(next)
            date = next.0.end
        }
        return result
    }
}
