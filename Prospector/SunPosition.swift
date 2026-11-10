import Foundation
import simd

struct SiteLocation: Decodable, Hashable, Sendable {
    let latitude: Double
    let northAngleDegrees: Double

    var isValid: Bool {
        (-90...90).contains(latitude) && northAngleDegrees.isFinite
    }

    func directionTowardSun(at moment: SunMoment) -> SIMD3<Float>? {
        let degrees = Double.pi / 180
        let latitude = latitude * degrees
        let declination = -23.44 * degrees * cos(2 * .pi / 365 * Double(moment.dayOfYear + 10))
        let hourAngle = 15 * (moment.solarHour - 12) * degrees

        let elevation = asin(sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hourAngle))
        guard elevation > 0 else { return nil }
        let azimuthFromNorth = .pi + atan2(sin(hourAngle), cos(hourAngle) * sin(latitude) - tan(declination) * cos(latitude))

        let clockwiseFromForward = northAngleDegrees * degrees + azimuthFromNorth
        let horizontal = cos(elevation)
        return SIMD3<Float>(
            Float(horizontal * sin(clockwiseFromForward)),
            Float(sin(elevation)),
            Float(-horizontal * cos(clockwiseFromForward))
        )
    }
}

struct BakedSun: Decodable, Hashable, Sendable {
    let moment: SunMoment
    let skyScale: Float
    let moments: [SunMoment]?
    let lightingPath: String?

    var selectableMoments: [SunMoment] {
        moments ?? [moment]
    }

    var isValid: Bool {
        skyScale.isFinite && skyScale > 0 && selectableMoments.contains(moment) && (moments == nil) == (lightingPath == nil)
    }
}

enum SunMoment: String, CaseIterable, Identifiable, Hashable, Sendable, Decodable {
    case summerEarlyMorning
    case summerMorning
    case summerNoon
    case summerEvening
    case equinoxMorning
    case equinoxNoon
    case equinoxEvening
    case winterMorning
    case winterNoon
    case winterAfternoon

    var id: Self { self }

    var title: String {
        switch self {
        case .summerMorning: "21 June, 08:00"
        case .summerNoon: "21 June, noon"
        case .summerEvening: "21 June, 18:00"
        case .equinoxNoon: "21 March, noon"
        case .winterMorning: "21 December, 10:00"
        case .winterNoon: "21 December, noon"
        case .summerEarlyMorning: "21 June, 06:00"
        case .equinoxMorning: "21 March, 07:30"
        case .equinoxEvening: "21 March, 16:30"
        case .winterAfternoon: "21 December, 14:00"
        }
    }

    var dayOfYear: Int {
        switch self {
        case .summerMorning, .summerNoon, .summerEvening, .summerEarlyMorning: 172
        case .equinoxNoon, .equinoxMorning, .equinoxEvening: 80
        case .winterMorning, .winterNoon, .winterAfternoon: 355
        }
    }

    var solarHour: Double {
        switch self {
        case .summerMorning: 8
        case .summerEvening: 18
        case .winterMorning: 10
        case .summerEarlyMorning: 6
        case .equinoxMorning: 7.5
        case .equinoxEvening: 16.5
        case .winterAfternoon: 14
        case .summerNoon, .equinoxNoon, .winterNoon: 12
        }
    }
}
