@preconcurrency import CoreLocation
import Foundation
import Observation

public struct HourlyForecastPoint: Identifiable, Equatable, Sendable {
    public var id: String { hourLabel }
    public var hourLabel: String
    public var temperature: Double
    public var weatherCode: Int
}

public struct DailyForecastPoint: Identifiable, Equatable, Sendable {
    public var id: String { dayLabel }
    public var dayLabel: String
    public var high: Double
    public var low: Double
    public var weatherCode: Int
}

public struct WeatherSnapshot: Equatable, Sendable {
    public var locationName: String
    public var currentTemp: Double
    public var feelsLike: Double
    public var highTemp: Double
    public var lowTemp: Double
    public var humidityPercent: Int
    public var windSpeed: Double
    public var uvIndex: Double
    public var pressureHpa: Int
    public var weatherCode: Int
    public var isDaylight: Bool
    public var sunriseLabel: String
    public var sunsetLabel: String
    public var hourly: [HourlyForecastPoint]
    public var daily: [DailyForecastPoint]

    public var conditionDescription: String {
        Self.describe(code: weatherCode)
    }

    public var conditionSymbol: String {
        Self.symbol(code: weatherCode, isDay: isDaylight)
    }

    public static func describe(code: Int) -> String {
        switch code {
        case 0: return "Clear sky"
        case 1, 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51...57: return "Drizzle"
        case 61...67, 80...82: return "Rain"
        case 71...77, 85...86: return "Snow"
        case 95...99: return "Thunderstorm"
        default: return "Fair"
        }
    }

    public static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85...86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.sun.fill"
        }
    }
}

/// Live forecast fetched cleanly from Open-Meteo (zero API key required).
@MainActor
@Observable
public final class WeatherService {
    public private(set) var snapshot: WeatherSnapshot?
    public private(set) var isLoading = false
    public private(set) var errorText: String?

    public init() {}

    public func refresh(city: String, unit: WeatherUnit, fallbackCoordinate: CLLocationCoordinate2D? = nil) {
        isLoading = true
        errorText = nil

        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        Task.detached(priority: .utility) {
            do {
                let targetCoord: (lat: Double, lon: Double, name: String)
                if !trimmedCity.isEmpty {
                    targetCoord = try await Self.geocode(city: trimmedCity)
                } else if let fallbackCoordinate {
                    targetCoord = (fallbackCoordinate.latitude, fallbackCoordinate.longitude, "Local")
                } else {
                    targetCoord = (37.7749, -122.4194, "San Francisco")
                }

                let fetched = try await Self.fetchForecast(
                    lat: targetCoord.lat,
                    lon: targetCoord.lon,
                    locationName: targetCoord.name,
                    unit: unit
                )
                await MainActor.run { [weak self] in
                    self?.snapshot = fetched
                    self?.isLoading = false
                    self?.errorText = nil
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isLoading = false
                    self?.errorText = "Unable to refresh weather."
                }
            }
        }
    }

    nonisolated private static func geocode(city: String) async throws -> (lat: Double, lon: Double, name: String) {
        let encoded = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city
        guard let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=en&format=json") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(GeocodeResponse.self, from: data)
        guard let first = decoded.results?.first else {
            throw URLError(.cannotFindHost)
        }
        return (first.latitude, first.longitude, first.name)
    }

    nonisolated private static func fetchForecast(
        lat: Double,
        lon: Double,
        locationName: String,
        unit: WeatherUnit
    ) async throws -> WeatherSnapshot {
        let tempUnit = (unit == .celsius) ? "celsius" : "fahrenheit"
        let windUnit = (unit == .celsius) ? "kmh" : "mph"
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,surface_pressure,wind_speed_10m&hourly=temperature_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max&temperature_unit=\(tempUnit)&wind_speed_unit=\(windUnit)&timezone=auto"
        guard let url = URL(string: urlStr) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        let res = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

        let isoOut = DateFormatter()
        isoOut.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let hrFmt = DateFormatter()
        hrFmt.dateFormat = "ha"
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEE"
        let dayInFmt = DateFormatter()
        dayInFmt.dateFormat = "yyyy-MM-dd"

        var hourlyPoints: [HourlyForecastPoint] = []
        let now = Date()
        for (idx, tStr) in res.hourly.time.enumerated() where hourlyPoints.count < 8 {
            if let dt = isoOut.date(from: tStr), dt >= now.addingTimeInterval(-3600) {
                let label = hrFmt.string(from: dt).lowercased()
                let tVal = idx < res.hourly.temperature_2m.count ? res.hourly.temperature_2m[idx] : res.current.temperature_2m
                let wCode = idx < res.hourly.weather_code.count ? res.hourly.weather_code[idx] : res.current.weather_code
                hourlyPoints.append(HourlyForecastPoint(hourLabel: label, temperature: tVal, weatherCode: wCode))
            }
        }

        var dailyPoints: [DailyForecastPoint] = []
        for (idx, dStr) in res.daily.time.enumerated() where idx < 7 {
            let label = dayInFmt.date(from: dStr).map { dayFmt.string(from: $0) } ?? dStr
            let hi = idx < res.daily.temperature_2m_max.count ? res.daily.temperature_2m_max[idx] : res.current.temperature_2m
            let lo = idx < res.daily.temperature_2m_min.count ? res.daily.temperature_2m_min[idx] : res.current.temperature_2m
            let code = idx < res.daily.weather_code.count ? res.daily.weather_code[idx] : res.current.weather_code
            dailyPoints.append(DailyForecastPoint(dayLabel: label, high: hi, low: lo, weatherCode: code))
        }

        let sunrise = res.daily.sunrise.first.flatMap { isoOut.date(from: $0) }.map {
            let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: $0)
        } ?? "—"
        let sunset = res.daily.sunset.first.flatMap { isoOut.date(from: $0) }.map {
            let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: $0)
        } ?? "—"

        return WeatherSnapshot(
            locationName: locationName,
            currentTemp: res.current.temperature_2m,
            feelsLike: res.current.apparent_temperature,
            highTemp: res.daily.temperature_2m_max.first ?? res.current.temperature_2m,
            lowTemp: res.daily.temperature_2m_min.first ?? res.current.temperature_2m,
            humidityPercent: Int(round(res.current.relative_humidity_2m)),
            windSpeed: res.current.wind_speed_10m,
            uvIndex: res.daily.uv_index_max.first ?? 0,
            pressureHpa: Int(round(res.current.surface_pressure)),
            weatherCode: res.current.weather_code,
            isDaylight: res.current.is_day == 1,
            sunriseLabel: sunrise,
            sunsetLabel: sunset,
            hourly: hourlyPoints,
            daily: dailyPoints
        )
    }

    private struct GeocodeResponse: Decodable {
        struct Item: Decodable { let name: String; let latitude: Double; let longitude: Double }
        let results: [Item]?
    }

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let relative_humidity_2m: Double
            let apparent_temperature: Double
            let is_day: Int
            let weather_code: Int
            let surface_pressure: Double
            let wind_speed_10m: Double
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double]
            let weather_code: [Int]
        }
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let sunrise: [String]
            let sunset: [String]
            let uv_index_max: [Double]
        }
        let current: Current
        let hourly: Hourly
        let daily: Daily
    }
}
