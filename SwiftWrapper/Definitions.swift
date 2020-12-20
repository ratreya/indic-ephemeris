/*
* IndicEphemeris is a fluent Swift interface to Swiss Ephemeris with Indic Astrology specific extensions.
* Copyright (C) 2020 Ranganath Atreya
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
*/

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
    
    static func > (left: Planet, right: Planet) -> Bool { left.rawValue > right.rawValue }
    static func >= (left: Planet, right: Planet) -> Bool { left.rawValue >= right.rawValue }
    static func < (left: Planet, right: Planet) -> Bool { left.rawValue < right.rawValue }
    static func <= (left: Planet, right: Planet) -> Bool { left.rawValue <= right.rawValue }

    private static let properties: [Planet: (vimshottariRatio: Double, symbol:  Character, avgSpeed: Double, maxSpeed: Double, retrograde: Double, synodicPeriod: Double)] = [
        .Sun: (6/120, "\u{2609}", 0.985628, 1.033942, 0, 0),
        .Moon: (10/120, "\u{263D}", 13.176157, 20.981417, 0, 0),
        .Mercury: (17/120, "\u{263F}", 0.985586, 2.212896, 21, 116),
        .Venus: (20/120, "\u{2640}", 0.983066, 1.266983, 41, 584),
        .Mars: (7/120, "\u{2642}", 0.523740, 0.797004, 72, 780),
        .Jupiter: (16/120, "\u{2643}", 0.083393, 0.244502, 121, 399),
        .Saturn: (19/120, "\u{2644}", 0.033544, 0.134413, 138, 378),
        .NorthNode: (18/120, "\u{260A}", -0.053040, 0.032170, 0, 0),
        .SouthNode: (7/120, "\u{260B}", -0.053040, 0.032170, 0, 0)
    ]
    
    /**
     Dasha period in years of the given planet divided by 120 years.
     */
    public var vimshottariRatio: Double { Planet.properties[self]!.vimshottariRatio }
    
    /**
     Unicode symbol for the given planet.
     */
    public var symbol: Character { Planet.properties[self]!.symbol }
    
    /**
     *Approximate* average speed in degrees / day for the given planet.
     - Note: Calculated using one degree samples over 50 revolutions, 25 before ReferenceDate and 25 after, for each planet. See `IndicEphemerisTest.testGetSpeeds()`.
     */
    public var avgSpeed: Double { Planet.properties[self]!.avgSpeed }
    
    /**
     *Approximate* maximum speed in degrees / day for the given planet.
     - Note: Calculated using one degree samples over 50 revolutions, 25 before ReferenceDate and 25 after, for each planet. See `IndicEphemerisTest.testGetSpeeds()`.
     */
    public var maxSpeed: Double { Planet.properties[self]!.maxSpeed }
    
    /**
     Average numbers of seconds that the given planet spends in retrograde motion.
     - Note: Obtained from [Wikipedia](https://en.wikipedia.org/wiki/Apparent_retrograde_motion).
     */
    public var retrograde: Double { Planet.properties[self]!.retrograde * Calendar.Component.day.seconds }
    
    /**
     Average numbers of seconds between ceneters of retrograde periods, also called *synodic period*.
     - Note: Obtained from [Wikipedia](https://en.wikipedia.org/wiki/Apparent_retrograde_motion).
     */
    public var synodicPeriod: Double { Planet.properties[self]!.synodicPeriod * Calendar.Component.day.seconds }
}

public enum Nakshatra: Int, CaseIterable {
    case Ashwini = 0, Bharani, Krittika, Rohini, Mrigashira, Ardra, Punarvasu, Pushya, Ashlesha, Magha, PurvaPhalguni, UttaraPhalguni, Hasta, Chitra, Svati, Vishakha, Anuradha, Jyeshtha, Mula, PurvaAshadha, UttaraAshadha, Shravana, Dhanishta, Shatabhisha, PurvaBhadrapada, UttaraBhadrapada, Revati

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
    init(degree: Int, minute: Int, second: Int) {
        self.init(degree + minute/60 + second/3600)
    }
    
    var degreeMinuteSecond: (degree: Int, minute: Int, second: Int) {
        let seconds = Int(self * 3600)
        return (seconds / 3600, (seconds % 3600) / 60, (seconds % 3600) % 60)
    }
}

public typealias NakshatraLocation = (degrees: Int, nakshatra: Nakshatra, minutes: Int, seconds: Int)
public typealias HouseLocation = (degrees: Int, house: House, minutes: Int, seconds: Int)

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
    
    public func houseLocation() throws -> HouseLocation {
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
    
    public func nakshatraLocation() -> NakshatraLocation {
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
internal let lifetimeInSeconds = lifetimeInYears * Calendar.Component.year.seconds
internal let secondsPerNakshatra = 48000.0
