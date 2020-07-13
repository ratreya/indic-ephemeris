//
//  Common.swift
//  SwiftEphemeris
//
//  Created by Atreya Ranganath on 7/10/20.
//  Copyright © 2020 Daivajnanam. All rights reserved.
//

import Foundation

enum EphemerisError: Error {
    case runtimeError(String)
}

public enum House: Int, CaseIterable {
    case Aries = 0, Taurus, Gemini, Cancer, Leo, Virgo, Libra, Scorpio, Sagittarius, Capricorn, Aquarius, Pisces
}

public enum Planet: Int, CaseIterable {
    case Sun = 0, Moon, Mercury, Venus, Mars, Jupiter, Saturn, NorthNode, SouthNode
}

extension Planet {
    private static let properties: [Planet: (dashaPeriod: Int, symbol:  Character)] = [
        .Sun: (6, "\u{2609}"),
        .Moon: (10, "\u{263D}"),
        .Mercury: (17, "\u{263F}"),
        .Venus: (20, "\u{2640}"),
        .Mars: (7, "\u{2642}"),
        .Jupiter: (16, "\u{2643}"),
        .Saturn: (19, "\u{2644}"),
        .NorthNode: (18, "\u{260A}"),
        .SouthNode: (7, "\u{260B}")
    ]
    
    public var dashaPeriod: Int { Planet.properties[self]!.dashaPeriod }
    public var symbol: Character { Planet.properties[self]!.symbol }
}

public enum Nakshatra: Int, CaseIterable {
    case Ashwini = 0, Bharani, Krittika, Rohini, Mrigashira, Ardra, Punarvasu, Pushya, Ashlesha, Magha, PurvaPhalguni, UttaraPhalguni, Hasta, Chitra, Svati, Vishakha, Anuradha, Jyeshtha, Mula, PurvaAshadha, UttaraAshadha, Shravana, Dhanishta, Shatabhisha, PurvaBhadrapada, UttaraBhadrapada, Revati
}

extension Nakshatra {
    private static let properties: [Nakshatra: (ruler: Planet, deity: String)] = [
        .Ashwini: (.SouthNode, "Ashwinau"),
        .Bharani: (.Venus, "Yama"),
        .Krittika: (.Sun, "Agni"),
        .Rohini: (.Moon, "Prajapati"),
        .Mrigashira: (.Mars, "Soma"),
        .Ardra: (.NorthNode, "Rudra"),
        .Punarvasu: (.Jupiter, "Aditi"),
        .Pushya: (.Saturn, "Brhaspati"),
        .Ashlesha: (.Mercury, "Naga"),
        .Magha: (.SouthNode, "Pitr"),
        .PurvaPhalguni: (.Venus, "Aryaman"),
        .UttaraPhalguni: (.Sun, "Bhaga"),
        .Hasta: (.Moon, "Savitr"),
        .Chitra: (.Mars, "Vishwakarma"),
        .Svati: (.NorthNode, "Vayu"),
        .Vishakha: (.Jupiter, "Indra"),
        .Anuradha: (.Saturn, "Mitra"),
        .Jyeshtha: (.Mercury, "Indra"),
        .Mula: (.SouthNode, "Nirrti"),
        .PurvaAshadha: (.Venus, "Apah"),
        .UttaraAshadha: (.Sun, "Vishvedeva"),
        .Shravana: (.Moon, "Vishnu"),
        .Dhanishta: (.Mars, "Vasu"),
        .Shatabhisha: (.NorthNode, "Varuna"),
        .PurvaBhadrapada: (.Jupiter, "Ajaikapada"),
        .UttaraBhadrapada: (.Saturn, "Ahir Budhyana"),
        .Revati: (.Mercury, "Pushan"),
    ]
    
    public var ruler: Planet { Nakshatra.properties[self]!.ruler }
    public var deity: String { Nakshatra.properties[self]!.deity }
}

extension Double {
    var degreeMinuteSecond: (degree: Int, minute: Int, second: Int) {
        let seconds = Int(self * 3600)
        return (seconds / 3600, (seconds % 3600) / 60, (seconds % 3600) % 60)
    }
}

public struct Position {
    public let longitude: Double
    public let latitude: Double?
    public let distance: Double?
    /**
     Latitudinal speed. Not present for Ascendant.
     - Note: negative speed implies retrograde motion.
     */
    public let speed: Double?
    
    public init(logitude: Double, latitude: Double? = nil, distance: Double? = nil, speed: Double? = nil) {
        self.longitude = logitude
        self.latitude = latitude
        self.distance = distance
        self.speed = speed
    }
    
    public func houseLocation() throws -> (degrees: Int, house: House, minutes: Int, seconds: Int) {
        let degrees: UnsafeMutablePointer<Int32> = UnsafeMutablePointer.allocate(capacity: 1)
        let minutes: UnsafeMutablePointer<Int32> = UnsafeMutablePointer.allocate(capacity: 1)
        let seconds: UnsafeMutablePointer<Int32> = UnsafeMutablePointer.allocate(capacity: 1)
        let sign: UnsafeMutablePointer<Int32> = UnsafeMutablePointer.allocate(capacity: 1)
        defer {
            degrees.deallocate()
            minutes.deallocate()
            seconds.deallocate()
            sign.deallocate()
        }
        swe_split_deg(longitude, SE_SPLIT_DEG_ROUND_SEC | SE_SPLIT_DEG_ZODIACAL, degrees, minutes, seconds, nil, sign)
        return (Int(degrees.pointee), House(rawValue: Int(sign.pointee))!, Int(minutes.pointee), Int(seconds.pointee))
    }
    
    public func nakshatraLocation() -> (degrees: Int, nakshatra: Nakshatra, minutes: Int, seconds: Int) {
        let degrees: UnsafeMutablePointer<Int32> = UnsafeMutablePointer.allocate(capacity: 1)
        let minutes: UnsafeMutablePointer<Int32> = UnsafeMutablePointer.allocate(capacity: 1)
        let seconds: UnsafeMutablePointer<Int32> = UnsafeMutablePointer.allocate(capacity: 1)
        let sign: UnsafeMutablePointer<Int32> = UnsafeMutablePointer.allocate(capacity: 1)
        defer {
            degrees.deallocate()
            minutes.deallocate()
            seconds.deallocate()
            sign.deallocate()
        }
        swe_split_deg(longitude, SE_SPLIT_DEG_ROUND_SEC | SE_SPLIT_DEG_NAKSHATRA, degrees, minutes, seconds, nil, sign)
        return (Int(degrees.pointee), Nakshatra(rawValue: Int(sign.pointee))!, Int(minutes.pointee), Int(seconds.pointee))
    }
}

public struct Phase {
    public let angle: Double
    public let illunation: Double
    public let elongation: Double
    public let diameter: Double
    public let magnitude: Double

    public init(angle: Double, illunation: Double, elongation: Double, diameter: Double, magnitude: Double) {
        self.angle = angle
        self.illunation = illunation
        self.elongation = elongation
        self.diameter = diameter
        self.magnitude = magnitude
    }
}

public struct Place {
    public let placeId: String
    public let timezone: TimeZone
    public let longitude: Double
    public let latitude: Double
    public let altitude: Double

    public init(placeId: String, timezone: TimeZone, latitude: Double, longitude: Double, altitude: Double) {
        self.placeId = placeId
        self.timezone = timezone
        self.longitude = longitude
        self.latitude = latitude
        self.altitude = altitude
    }
}

public class MetaDasha: CustomStringConvertible {
    let period: DateInterval
    let planet: Planet
    let subDasha: [MetaDasha]?

    public var description: String {
        return "Period: \(period), Planet: \(planet)"
    }
    
    internal init(period: DateInterval, planet: Planet, subDasha: [MetaDasha]? = nil) {
        self.period = period
        self.planet = planet
        self.subDasha = subDasha
    }
}

public enum Ayanamsha: Int, CaseIterable {
    case FaganBradley = 0, Lahiri, Deluce, Raman, Ushashashi, Krishnamurti, DjwhalKhul, Yukteshwar, JnBhasin, BabylKugler1, BabylKugler2, BabylKugler3, BabylHuber, BabylEtpsc, Aldebaran15Tau, Hipparchos, Sassanian, Galcent0Sag, J2000, J1900, B1950, Suryasiddhanta, SuryasiddhantaMsun, Aryabhata, AryabhataMsun, SsRevati, SsCitra, TrueCitra, TrueRevati, TruePushya, GalcentRgbrand, GalequIau1958, GalequTrue, GalequMula, GalalignMardyks, TrueMula, GalcentMulaWilhelm, Aryabhata522, BabylBritton, TrueSheoran, GalcentCochrane, GalequFiorenza, ValensMoon
}
