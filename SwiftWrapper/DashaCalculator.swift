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
    static func + (left: DashaType, right: Int) -> DashaType { DashaType(rawValue: min(left.rawValue + right, DashaType.Pratyantardasha.rawValue))! }
}

let dashaOrder: [Planet] = [.SouthNode, .Venus, .Sun, .Moon, .Mars, .NorthNode, .Jupiter, .Saturn, .Mercury]

public class MetaDasha: CustomStringConvertible {
    public let planet: Planet
    public let type: DashaType
    internal (set) public var period: DateInterval
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

public enum DashaMarker {
    case ascendent
    case planet(Planet)
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
    func vimshottari(interval: DateInterval, starting: Planet, elapsed: Double, depth: DashaType = .Mahadasha) -> [MetaDasha] {
        let totalDuration = interval.duration + elapsed
        var firstPlanet = starting
        var index = dashaOrder.firstIndex(of: starting)!
        var residual = elapsed
        while residual >= 0 {
            firstPlanet = dashaOrder[index]
            residual -= firstPlanet.vimshottariRatio * totalDuration
            index = (index + 1) % dashaOrder.count
        }
        let firstPeriod = DateInterval(start: interval.start, duration: abs(residual))
        let firstDasha = MetaDasha(period: firstPeriod, planet: firstPlanet, type: depth)
        if depth < ephemeris.config.maxDashaDepth {
            let subElapsed = firstPlanet.vimshottariRatio * totalDuration + residual
            firstDasha.subDasha = vimshottari(interval: firstPeriod, starting: firstPlanet, elapsed: subElapsed, depth: depth + 1)
        }
        // Rest of the periods naturally follow in order
        var result = [firstDasha]
        var next = dashaOrder.firstIndex(of: firstPlanet)!
        var date = firstPeriod.end
        while date < interval.end {
            next = (next + 1) % dashaOrder.count
            let nextPlanet = dashaOrder[next]
            let nextPeriod = DateInterval(start: date, duration: nextPlanet.vimshottariRatio * totalDuration)
            let subDasha = MetaDasha(period: nextPeriod, planet: nextPlanet, type: depth)
            if depth < ephemeris.config.maxDashaDepth {
                subDasha.subDasha = vimshottari(interval: nextPeriod, starting: nextPlanet, elapsed: 0, depth: depth + 1)
            }
            result.append(subDasha)
            date = nextPeriod.end
        }
        return result
    }
    
    func overlapping(dashas: [MetaDasha], range: DateInterval, strict: Bool = false) -> [MetaDasha] {
        let mahas = dashas.filter() { (maha) -> Bool in maha.period.intersects(range) }
        if strict {
            mahas.forEach { $0.period = $0.period.intersection(with: range)! }
        }
        for maha in mahas {
            if let subDasha = maha.subDasha {
                maha.subDasha = overlapping(dashas: subDasha, range: range, strict: strict)
            }
        }
        return mahas
    }
    
    public func vimshottari(starting from: DashaMarker = .planet(.Moon)) throws -> (prenatal: [MetaDasha], postnatal: [MetaDasha]) {
        var starting: NakshatraLocation
        switch from {
        case .planet(let planet):
            starting = try ephemeris.position(for: planet).nakshatraLocation()
        case .ascendent:
            starting = try ephemeris.ascendant().nakshatraLocation()
        }
        let elapsedAngle = Double(starting.degrees*3600 + starting.minutes*60 + starting.seconds)
        let elapsedTime = elapsedAngle/secondsPerNakshatra * starting.nakshatra.ruler.vimshottariRatio * lifetimeInSeconds
        var prenatal = vimshottari(interval: DateInterval(start: ephemeris.dateUTC.advanced(by: -elapsedTime), duration: lifetimeInSeconds), starting: starting.nakshatra.ruler, elapsed: 0)
        // Cut prenatal dasha interval to the point of birth
        prenatal = overlapping(dashas: prenatal, range: DateInterval(start: ephemeris.dateUTC.advanced(by: -elapsedTime), duration: elapsedTime), strict: true)
        let postnatal = vimshottari(interval: DateInterval(start: ephemeris.dateUTC, duration: lifetimeInSeconds-elapsedTime), starting: starting.nakshatra.ruler, elapsed: elapsedTime)
        return (prenatal, postnatal)
    }

    public func vimshottari(overlapping range: DateInterval, starting from: DashaMarker = .planet(.Moon)) throws -> [MetaDasha] {
        return overlapping(dashas: try vimshottari(starting: from).postnatal, range: range)
    }
}
