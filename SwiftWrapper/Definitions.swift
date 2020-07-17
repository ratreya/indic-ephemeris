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
    
    static func + (left: House, right: Int) -> House {
        House(rawValue: (left.rawValue + right) % 12)!
    }

    static func - (left: House, right: Int) -> House {
        return left + (12 - (right % 12))
    }
}

public enum Planet: Int, CaseIterable {
    case Sun = 0, Moon, Mercury, Venus, Mars, Jupiter, Saturn, NorthNode=11,
        SouthNode=108 // Some number that is invalid for SWE; we will special case it
}

/**
 For all position to time calculations, we are sampling position at 30 degrees (1 house) of spatial granularity.
 So, temporal sampling should be at such an interval within which the planet will move less than 30 degrees.
*/
extension Planet {
    private static let properties: [Planet: (dashaRatio: Double, symbol:  Character, sampling: Calendar.Component)] = [
        .Sun: (6/120, "\u{2609}", .day),
        .Moon: (10/120, "\u{263D}", .day),
        .Mercury: (17/120, "\u{263F}", .day),
        .Venus: (20/120, "\u{2640}", .day),
        .Mars: (7/120, "\u{2642}", .month),
        .Jupiter: (16/120, "\u{2643}", .month),
        .Saturn: (19/120, "\u{2644}", .month),
        .NorthNode: (18/120, "\u{260A}", .year),
        .SouthNode: (7/120, "\u{260B}", .year)
    ]
    
    public var dashaRatio: Double { Planet.properties[self]!.dashaRatio }
    public var symbol: Character { Planet.properties[self]!.symbol }
    public var sampling: Calendar.Component { Planet.properties[self]!.sampling }
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
    
    internal init(logitude: Double, latitude: Double? = nil, distance: Double? = nil, speed: Double? = nil) {
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

    internal init(angle: Double, illunation: Double, elongation: Double, diameter: Double, magnitude: Double) {
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

public enum Ayanamsha: Int, CaseIterable {
    case FaganBradley = 0, Lahiri, Deluce, Raman, Ushashashi, Krishnamurti, DjwhalKhul, Yukteshwar, JnBhasin, BabylKugler1, BabylKugler2, BabylKugler3, BabylHuber, BabylEtpsc, Aldebaran15Tau, Hipparchos, Sassanian, Galcent0Sag, J2000, J1900, B1950, Suryasiddhanta, SuryasiddhantaMsun, Aryabhata, AryabhataMsun, SsRevati, SsCitra, TrueCitra, TrueRevati, TruePushya, GalcentRgbrand, GalequIau1958, GalequTrue, GalequMula, GalalignMardyks, TrueMula, GalcentMulaWilhelm, Aryabhata522, BabylBritton, TrueSheoran, GalcentCochrane, GalequFiorenza, ValensMoon
}

internal let lifetimeInYears = 120.0
internal let lifetimeInSeconds = lifetimeInYears * 365.0 * 24.0 * 60.0 * 60.0
internal let secondsPerNakshatra = 48000.0
