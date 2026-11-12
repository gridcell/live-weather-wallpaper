import Foundation

enum WeatherKind: String, CaseIterable {
    case clear, partlyCloudy, cloudy, fog, drizzle, rain, heavyRain, snow, heavySnow, thunderstorm

    var title: String {
        switch self {
        case .clear: return "Clear"
        case .partlyCloudy: return "Partly Cloudy"
        case .cloudy: return "Cloudy"
        case .fog: return "Fog"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .heavyRain: return "Heavy Rain"
        case .snow: return "Snow"
        case .heavySnow: return "Heavy Snow"
        case .thunderstorm: return "Thunderstorm"
        }
    }

    func symbolName(isDay: Bool) -> String {
        switch self {
        case .clear: return isDay ? "sun.max" : "moon.stars"
        case .partlyCloudy: return isDay ? "cloud.sun" : "cloud.moon"
        case .cloudy: return "cloud"
        case .fog: return "cloud.fog"
        case .drizzle: return "cloud.drizzle"
        case .rain: return "cloud.rain"
        case .heavyRain: return "cloud.heavyrain"
        case .snow, .heavySnow: return "cloud.snow"
        case .thunderstorm: return "cloud.bolt.rain"
        }
    }

    /// Maps a WMO weather interpretation code (as returned by Open-Meteo).
    init(wmoCode: Int) {
        switch wmoCode {
        case 0: self = .clear
        case 1, 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51...57: self = .drizzle
        case 61, 63, 66, 80, 81: self = .rain
        case 65, 67, 82: self = .heavyRain
        case 71, 73, 77, 85: self = .snow
        case 75, 86: self = .heavySnow
        case 95...99: self = .thunderstorm
        default: self = .cloudy
        }
    }
}

struct Weather: Equatable {
    var kind: WeatherKind
    var isDay: Bool
    /// Horizontal wind component in km/h; positive blows toward the right of the screen.
    var windX: Double
    var temperatureC: Double?
}

enum WeatherService {
    private struct Response: Decodable {
        struct Current: Decodable {
            let weather_code: Int
            let is_day: Int
            let temperature_2m: Double
            let wind_speed_10m: Double
            let wind_direction_10m: Double
        }
        let current: Current
    }

    static func fetch(latitude: Double, longitude: Double) async throws -> Weather {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "weather_code,is_day,temperature_2m,wind_speed_10m,wind_direction_10m"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let current = try JSONDecoder().decode(Response.self, from: data).current
        // Wind direction is where the wind comes from, so 270° (westerly) blows toward +x.
        let windX = -sin(current.wind_direction_10m * .pi / 180) * current.wind_speed_10m
        return Weather(
            kind: WeatherKind(wmoCode: current.weather_code),
            isDay: current.is_day == 1,
            windX: windX,
            temperatureC: current.temperature_2m
        )
    }
}
