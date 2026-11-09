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

    var isValid: Bool {
        skyScale.isFinite && skyScale > 0
    }
}

enum SunMoment: String, CaseIterable, Identifiable, Hashable, Sendable, Decodable {
    case summerMorning
    case summerNoon
    case summerEvening
    case equinoxNoon
    case winterMorning
    case winterNoon

    var id: Self { self }

    var title: String {
        switch self {
        case .summerMorning: "21 June, 08:00"
        case .summerNoon: "21 June, noon"
        case .summerEvening: "21 June, 18:00"
        case .equinoxNoon: "21 March, noon"
        case .winterMorning: "21 December, 10:00"
        case .winterNoon: "21 December, noon"
        }
    }

    var dayOfYear: Int {
        switch self {
        case .summerMorning, .summerNoon, .summerEvening: 172
        case .equinoxNoon: 80
        case .winterMorning, .winterNoon: 355
        }
    }

    var solarHour: Double {
        switch self {
        case .summerMorning: 8
        case .summerEvening: 18
        case .winterMorning: 10
        case .summerNoon, .equinoxNoon, .winterNoon: 12
        }
    }
}
