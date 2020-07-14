//
//  DashaExtension.swift
//  SwiftEphemeris
//
//  Created by Atreya Ranganath on 7/13/20.
//  Copyright © 2020 Daivajnanam. All rights reserved.
//

import Foundation

public enum DashaType: Int, CaseIterable {
    case Maha=0, Antar, Pratyantar
}

public class MetaDasha: CustomStringConvertible {
    public let period: DateInterval
    public let planet: Planet
    public let type: DashaType
    internal (set) public var subDasha: [MetaDasha]?
    unowned private (set) public var supraDasha: MetaDasha?

    public var description: String {
        var response = "Period: \(period), Planet: \(planet), Type: \(type)"
        if let sub = subDasha {
            let indent = "\n" + String(repeating: "\t", count: type.rawValue + 1)
            response += indent
            response += sub.map( { $0.description } ).joined(separator: indent)
        }
        return response
    }
    
    internal init(period: DateInterval, planet: Planet, type: DashaType, subDasha: [MetaDasha]? = nil) {
        self.period = period
        self.planet = planet
        self.subDasha = subDasha
        self.type = type
        self.subDasha?.forEach() { $0.supraDasha = self }
    }
}

extension IndicEphemeris {
    internal static let dashaOrder: [Planet] = [.SouthNode, .Venus, .Sun, .Moon, .Mars, .NorthNode, .Jupiter, .Saturn, .Mercury]

    internal enum DashaStart {
        case MahaDasha(planet: Planet)
        case Moon(position: Position)
    }

    internal func dashas(for interval: DateInterval, starting from: DashaStart, level: Int) -> [MetaDasha] {
        // Specially handle the first period
        var firstPeriod: DateInterval
        var firstPlanet: Planet
        switch from {
        case .MahaDasha(let planet):
            firstPeriod = DateInterval(start: interval.start, duration: Double(planet.dashaPeriod)/lifetimeInYears * interval.duration)
            firstPlanet = planet
        case .Moon(let position):
            let natal = position.nakshatraLocation()
            let secondsElapsed = natal.degrees*60*60 + natal.minutes*60 + natal.seconds
            let total = Double(natal.nakshatra.ruler.dashaPeriod)/lifetimeInYears * interval.duration
            let remaining = (secondsPerNakshatra - Double(secondsElapsed))/secondsPerNakshatra * total
            firstPeriod = DateInterval(start: interval.start, duration: remaining)
            firstPlanet = natal.nakshatra.ruler
        }
        var firstDasha: MetaDasha
        var subDashas: [MetaDasha]? = nil
        if level <= 1 {
            subDashas = dashas(for: firstPeriod, starting: from, level: level + 1)
        }
        firstDasha = MetaDasha(period: firstPeriod, planet: firstPlanet, type: DashaType(rawValue: level)!, subDasha: subDashas)
        // Rest of the periods naturally follow in order
        var result = [firstDasha]
        var next = IndicEphemeris.dashaOrder.firstIndex(of: firstPlanet)!
        var date = firstPeriod.end
        while date < interval.end {
            next = (next + 1) % IndicEphemeris.dashaOrder.count
            let nextPlanet = IndicEphemeris.dashaOrder[next]
            let nextPeriod = DateInterval(start: date, duration: Double(nextPlanet.dashaPeriod)/lifetimeInYears * interval.duration)
            var nextSubDashas: [MetaDasha]? = nil
            if level <= 1 {
                nextSubDashas = dashas(for: nextPeriod, starting: .MahaDasha(planet: nextPlanet), level: level + 1)
            }
            result.append(MetaDasha(period: nextPeriod, planet: nextPlanet, type: DashaType(rawValue: level)!, subDasha: nextSubDashas))
            date = nextPeriod.end
        }
        return result
    }

    public func dashas() throws -> [MetaDasha] {
        return dashas(for: DateInterval(start: dateUTC, duration: lifetimeInSeconds), starting: .Moon(position: try position(for: .Moon)), level: 0)
    }

    public func dashas(overlapping range: DateInterval) throws -> [MetaDasha] {
        var mahas = try dashas()
        mahas = mahas.filter() { (maha) -> Bool in maha.period.intersects(range) }
        for maha in mahas {
            maha.subDasha = maha.subDasha?.filter() { (antar) -> Bool in antar.period.intersects(range) }
            for antar in maha.subDasha! {
                antar.subDasha = antar.subDasha?.filter()  { (patyantar) -> Bool in patyantar.period.intersects(range) }
            }
        }
        return mahas
    }

    public func dasha(for date: Date) throws -> (mahaDasha: (DateInterval, Planet), antarDasha: (DateInterval, Planet), paryantarDasha: (DateInterval, Planet)) {
        var mahas = try dashas()
        var result = [(DateInterval, Planet)]()
        for _ in 0...2 {
            for maha in mahas {
                if maha.period.contains(date) {
                    result.append((maha.period, maha.planet))
                    mahas = maha.subDasha ?? []
                    break
                }
            }
        }
        return (result[0], result[1], result[2])
    }
}
