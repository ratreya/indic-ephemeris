/*
* IndicEphemeris is a fluent Swift interface to Swiss Ephemeris with Indic Astrology specific extensions.
* Copyright (C) 2020 Ranganath Atreya
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
*/

import Foundation

public enum DashaType: Int, CaseIterable {
    case Mahadasha=0, Antardasha, Pratyantardasha
    
    static func < (left: DashaType, right: DashaType) -> Bool { left.rawValue < right.rawValue }
    static func + (left: DashaType, right: Int) -> DashaType { DashaType(rawValue: max(left.rawValue + right, DashaType.Pratyantardasha.rawValue))! }
}

let dashaOrder: [Planet] = [.SouthNode, .Venus, .Sun, .Moon, .Mars, .NorthNode, .Jupiter, .Saturn, .Mercury]

public class MetaDasha: CustomStringConvertible {
    public let period: DateInterval
    public let planet: Planet
    public let type: DashaType
    internal (set) public var subDasha: [MetaDasha]? {
        didSet {
            self.subDasha?.forEach() { $0.supraDasha = self }
        }
    }
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
    
    init(period: DateInterval, planet: Planet, type: DashaType, subDasha: [MetaDasha]? = nil) {
        self.period = period
        self.planet = planet
        self.subDasha = subDasha
        self.type = type
    }
}

public class DashaCalculator {
    private let ephemeris: IndicEphemeris
    
    public init(_ ephemeris: IndicEphemeris) {
        self.ephemeris = ephemeris
    }
    
    /**
     - Parameters:
        - duration: The time interval within which subdashas are desired. Usually, this is the duration of the uber-Dasha. For Maha-Dasha, this is 120 years starting from birth minus the `elapsed` time.
        - starting: The planet from which to start. This is the planet of the uber-Dasha. For Maha-Dasha, this is the ruler of the nakshatra that is occupied by the moon.
        - elapsed: Number of time seconds elapsed since the `starting` planet's cusp to the beginning of `duration`.
        - depth: The top-level `DashaType` that needs to be calculated. Initial call should always pass in `.Mahadasha`. 
     */
    func dashas(interval: DateInterval, starting: Planet, elapsed: Double, depth: DashaType = .Mahadasha) -> [MetaDasha] {
        let totalDuration = interval.duration + elapsed
        var firstPlanet = starting
        var index = dashaOrder.firstIndex(of: starting)!
        var residual = elapsed
        while residual >= 0 {
            firstPlanet = dashaOrder[index]
            residual -= firstPlanet.dashaRatio * totalDuration
            index = (index + 1) % dashaOrder.count
        }
        let firstPeriod = DateInterval(start: interval.start, duration: abs(residual))
        let firstDasha = MetaDasha(period: firstPeriod, planet: firstPlanet, type: depth)
        if depth < ephemeris.config.maxDashaDepth {
            let subElapsed = firstPlanet.dashaRatio * totalDuration + residual
            firstDasha.subDasha = dashas(interval: firstPeriod, starting: firstPlanet, elapsed: subElapsed, depth: depth + 1)
        }
        // Rest of the periods naturally follow in order
        var result = [firstDasha]
        var next = dashaOrder.firstIndex(of: firstPlanet)!
        var date = firstPeriod.end
        while date < interval.end {
            next = (next + 1) % dashaOrder.count
            let nextPlanet = dashaOrder[next]
            let nextPeriod = DateInterval(start: date, duration: nextPlanet.dashaRatio * totalDuration)
            let subDasha = MetaDasha(period: nextPeriod, planet: nextPlanet, type: depth)
            if depth < ephemeris.config.maxDashaDepth {
                subDasha.subDasha = dashas(interval: nextPeriod, starting: nextPlanet, elapsed: 0, depth: depth + 1)
            }
            result.append(subDasha)
            date = nextPeriod.end
        }
        return result
    }

    public func dashas() throws -> [MetaDasha] {
        let moon = try ephemeris.position(for: .Moon).nakshatraLocation()
        let elapsedAngle = Double(moon.degrees*3600 + moon.minutes*60 + moon.seconds)
        let elapsedTime = elapsedAngle/secondsPerNakshatra * moon.nakshatra.ruler.dashaRatio * lifetimeInSeconds
        return dashas(interval: DateInterval(start: ephemeris.dateUTC, duration: lifetimeInSeconds-elapsedTime), starting: moon.nakshatra.ruler, elapsed: elapsedTime)
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
}
