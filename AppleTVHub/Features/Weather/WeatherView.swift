import SwiftUI

struct WeatherView: View {
    let isActive: Bool

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = WeatherViewModel()

    private let metricColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.08, blue: 0.18), Color(red: 0.07, green: 0.20, blue: 0.34), Color(red: 0.12, green: 0.30, blue: 0.46)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    locationPicker

                    if let error = viewModel.errorMessage, viewModel.weather != nil {
                        staleDataBanner(error)
                    }

                    if viewModel.isLoading && viewModel.weather == nil {
                        loadingState
                    } else if let weather = viewModel.weather {
                        currentHero(weather)
                        todayMetrics(weather)
                        hourlyForecast(weather)
                        dailyForecast(weather)
                    } else {
                        errorState
                    }
                }
                .padding(.horizontal, 64)
                .padding(.vertical, 38)
            }
        }
        .task(id: refreshTaskID) {
            guard scenePhase == .active, isActive else { return }
            await viewModel.refresh(force: viewModel.weather == nil)

            guard !Task.isCancelled, scenePhase == .active, isActive else { return }
            await autoRefreshLoop()
        }
    }

    private var refreshTaskID: String {
        "\(scenePhase == .active ? "active" : "inactive")-\(isActive ? "visible" : "hidden")"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    Image(systemName: "cloud.sun.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 36))
                    Text("WEATHER CENTER")
                        .font(.system(size: 50, weight: .black, design: .rounded))
                }
                Text("Current conditions, hourly detail and a full 7-day outlook")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(viewModel.errorMessage == nil ? "Auto refresh · ~15 min" : "Retrying · ~2 min")
                    .font(.caption.bold())
                    .foregroundStyle(viewModel.errorMessage == nil ? Color.secondary : Color.orange)
                if let updated = viewModel.lastUpdated {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task { await viewModel.refresh(force: true) }
            } label: {
                if viewModel.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Refreshing")
                    }
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .disabled(viewModel.isLoading)
        }
    }

    private var locationPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(WeatherLocation.presets) { location in
                    Button {
                        Task { await viewModel.select(location) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.name).fontWeight(.bold())
                            Text(location.subtitle)
                                .font(.caption)
                                .foregroundStyle(viewModel.location == location ? Color.black.opacity(0.65) : Color.secondary)
                        }
                        .frame(minWidth: 190, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.location == location ? .white : .gray.opacity(0.28))
                    .foregroundStyle(viewModel.location == location ? .black : .white)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var loadingState: some View {
        HStack(spacing: 18) {
            ProgressView()
            Text("Loading weather…")
                .font(.title2)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private func currentHero(_ weather: OpenMeteoResponse) -> some View {
        HStack(spacing: 34) {
            VStack(spacing: 12) {
                Image(systemName: WeatherCode.symbol(weather.current.weatherCode))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 112))
                    .frame(width: 150, height: 130)
                Text(WeatherCode.description(weather.current.weatherCode))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(viewModel.location.name)
                    .font(.title.bold())
                Text("\(Int(weather.current.temperature2m.rounded()))°")
                    .font(.system(size: 104, weight: .black, design: .rounded))
                    .contentTransition(.numericText())
                Text("Feels like \(Int(weather.current.apparentTemperature.rounded()))°")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                Text("TODAY")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                if let high = weather.daily.temperature2mMax.first,
                   let low = weather.daily.temperature2mMin.first {
                    HStack(spacing: 26) {
                        Label("\(Int(high.rounded()))° high", systemImage: "arrow.up")
                        Label("\(Int(low.rounded()))° low", systemImage: "arrow.down")
                    }
                    .font(.title3.bold())
                }

                if let sunrise = weather.daily.sunrise?.first,
                   let sunset = weather.daily.sunset?.first {
                    HStack(spacing: 24) {
                        Label(timeLabel(sunrise, weather: weather), systemImage: "sunrise.fill")
                        Label(timeLabel(sunset, weather: weather), systemImage: "sunset.fill")
                    }
                    .font(.headline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 22))
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func todayMetrics(_ weather: OpenMeteoResponse) -> some View {
        LazyVGrid(columns: metricColumns, spacing: 16) {
            metricCard(title: "Humidity", value: "\(weather.current.relativeHumidity2m)%", symbol: "humidity.fill")
            metricCard(title: "Wind", value: "\(Int(weather.current.windSpeed10m.rounded())) mph", symbol: "wind")
            metricCard(title: "Gusts", value: "\(Int((weather.current.windGusts10m ?? 0).rounded())) mph", symbol: "tornado")
            metricCard(title: "Cloud Cover", value: "\(weather.current.cloudCover ?? 0)%", symbol: "cloud.fill")

            metricCard(title: "Precip Now", value: String(format: "%.2f in", weather.current.precipitation ?? 0), symbol: "drop.fill")
            metricCard(title: "Rain Chance", value: "\(weather.daily.precipitationProbabilityMax.first ?? 0)%", symbol: "umbrella.fill")
            metricCard(title: "UV Index", value: String(format: "%.1f", weather.daily.uvIndexMax?.first ?? 0), symbol: "sun.max.fill")
            metricCard(title: "Max Wind", value: "\(Int((weather.daily.windSpeed10mMax?.first ?? 0).rounded())) mph", symbol: "wind.circle.fill")
        }
    }

    private func metricCard(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 28, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.bold())
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func hourlyForecast(_ weather: OpenMeteoResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("NEXT 12 HOURS")
                    .font(.title2.bold())
                Spacer()
                Text("Focus a card and swipe to move through the timeline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(hourlyIndices(weather), id: \.self) { index in
                        HourlyForecastCard(
                            time: hourLabel(weather.hourly.time[index], weather: weather),
                            temperature: Int(weather.hourly.temperature2m[index].rounded()),
                            precipitation: weather.hourly.precipitationProbability[index],
                            weatherCode: weather.hourly.weatherCode[index],
                            wind: hourlyWind(weather, index: index)
                        )
                    }
                }
                .padding(.vertical, 16)
            }
        }
    }

    private func dailyForecast(_ weather: OpenMeteoResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("7-DAY OUTLOOK")
                .font(.title2.bold())

            HStack(spacing: 14) {
                ForEach(Array(0..<dailyCount(weather)), id: \.self) { index in
                    DailyForecastCard(
                        day: dayLabel(weather.daily.time[index], weather: weather),
                        weatherCode: weather.daily.weatherCode[index],
                        high: Int(weather.daily.temperature2mMax[index].rounded()),
                        low: Int(weather.daily.temperature2mMin[index].rounded()),
                        precipitation: weather.daily.precipitationProbabilityMax[index],
                        wind: dailyValue(weather.daily.windSpeed10mMax, index: index).map { Int($0.rounded()) }
                    )
                }
            }
        }
        .padding(.bottom, 48)
    }

    private var errorState: some View {
        VStack(spacing: 18) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 64))
            Text("Weather unavailable")
                .font(.title2.bold())
            Text(viewModel.errorMessage ?? "Try refreshing.")
                .foregroundStyle(.secondary)
            Button("Try Again") {
                Task { await viewModel.refresh(force: true) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 350)
    }

    private func staleDataBanner(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
            Text("Latest refresh failed. Showing the last successful forecast.")
                .fontWeight(.semibold)
            Spacer()
            Text(error)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
    }

    private func hourlyIndices(_ weather: OpenMeteoResponse) -> [Int] {
        let count = min(
            weather.hourly.time.count,
            weather.hourly.temperature2m.count,
            weather.hourly.precipitationProbability.count,
            weather.hourly.weatherCode.count
        )
        guard count > 0 else { return [] }

        let formatter = localHourlyFormatter(for: weather)
        let now = Date()
        let start = (0..<count).first { index in
            guard let date = formatter.date(from: weather.hourly.time[index]) else { return false }
            return date >= now.addingTimeInterval(-30 * 60)
        } ?? max(count - 1, 0)
        let end = min(start + 12, count)
        return start < end ? Array(start..<end) : []
    }

    private func dailyCount(_ weather: OpenMeteoResponse) -> Int {
        min(
            7,
            weather.daily.time.count,
            weather.daily.weatherCode.count,
            weather.daily.temperature2mMax.count,
            weather.daily.temperature2mMin.count,
            weather.daily.precipitationProbabilityMax.count
        )
    }

    private func hourlyWind(_ weather: OpenMeteoResponse, index: Int) -> Int? {
        guard let winds = weather.hourly.windSpeed10m, winds.indices.contains(index) else { return nil }
        return Int(winds[index].rounded())
    }

    private func dailyValue(_ values: [Double]?, index: Int) -> Double? {
        guard let values, values.indices.contains(index) else { return nil }
        return values[index]
    }

    private func hourLabel(_ isoLocal: String, weather: OpenMeteoResponse) -> String {
        let parser = localHourlyFormatter(for: weather)
        guard let date = parser.date(from: isoLocal) else { return isoLocal }

        let display = DateFormatter()
        display.locale = Locale(identifier: "en_US")
        display.timeZone = TimeZone(identifier: weather.timezone) ?? .current
        display.dateFormat = "h a"
        return display.string(from: date)
    }

    private func timeLabel(_ isoLocal: String, weather: OpenMeteoResponse) -> String {
        hourLabel(isoLocal, weather: weather)
    }

    private func dayLabel(_ dateString: String, weather: OpenMeteoResponse) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: weather.timezone) ?? .current
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dateString) else { return dateString }

        let display = DateFormatter()
        display.locale = Locale(identifier: "en_US")
        display.timeZone = parser.timeZone
        display.dateFormat = "EEE"
        return display.string(from: date)
    }

    private func localHourlyFormatter(for weather: OpenMeteoResponse) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: weather.timezone) ?? .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }

    private func autoRefreshLoop() async {
        while !Task.isCancelled {
            let wait: UInt64 = viewModel.errorMessage == nil
                ? 15 * 60 * 1_000_000_000
                : 2 * 60 * 1_000_000_000

            do {
                try await Task.sleep(nanoseconds: wait)
            } catch {
                return
            }

            guard scenePhase == .active, isActive else { return }
            await viewModel.refresh(force: true)
        }
    }
}

private struct HourlyForecastCard: View {
    let time: String
    let temperature: Int
    let precipitation: Int
    let weatherCode: Int
    let wind: Int?

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            Text(time)
                .font(.headline)
            Image(systemName: WeatherCode.symbol(weatherCode))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 40))
            Text("\(temperature)°")
                .font(.title2.bold())
            HStack(spacing: 10) {
                Label("\(precipitation)%", systemImage: "drop.fill")
                if let wind {
                    Label("\(wind)", systemImage: "wind")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 152, height: 188)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(isFocused ? 0.55 : 0.08), lineWidth: isFocused ? 3 : 1)
        }
        .scaleEffect(isFocused ? 1.06 : 1)
        .animation(.easeOut(duration: 0.12), value: isFocused)
        .focusable()
        .focused($isFocused)
        .zIndex(isFocused ? 1 : 0)
        .accessibilityLabel("\(time), \(temperature) degrees, \(WeatherCode.description(weatherCode)), \(precipitation) percent precipitation")
    }
}

private struct DailyForecastCard: View {
    let day: String
    let weatherCode: Int
    let high: Int
    let low: Int
    let precipitation: Int
    let wind: Int?

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            Text(day)
                .font(.headline)
            Image(systemName: WeatherCode.symbol(weatherCode))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 38))
            HStack(spacing: 8) {
                Text("\(high)°")
                    .fontWeight(.bold)
                Text("\(low)°")
                    .foregroundStyle(.secondary)
            }
            Label("\(precipitation)%", systemImage: "drop.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let wind {
                Label("\(wind) mph", systemImage: "wind")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 205)
        .padding(.vertical, 18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(isFocused ? 0.50 : 0.07), lineWidth: isFocused ? 3 : 1)
        }
        .scaleEffect(isFocused ? 1.035 : 1)
        .animation(.easeOut(duration: 0.12), value: isFocused)
        .focusable()
        .focused($isFocused)
    }
}
