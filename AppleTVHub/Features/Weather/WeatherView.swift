import SwiftUI

struct WeatherView: View {
    let isActive: Bool

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = WeatherViewModel()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.10, blue: 0.20), Color(red: 0.11, green: 0.24, blue: 0.38)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header
                    locationPicker

                    if let error = viewModel.errorMessage, viewModel.weather != nil {
                        staleDataBanner(error)
                    }

                    if viewModel.isLoading && viewModel.weather == nil {
                        HStack(spacing: 18) {
                            ProgressView()
                            Text("Loading weather…")
                                .font(.title2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 360)
                    } else if let weather = viewModel.weather {
                        currentConditions(weather)
                        hourlyForecast(weather)
                        dailyForecast(weather)
                    } else {
                        errorState
                    }
                }
                .padding(.horizontal, 70)
                .padding(.vertical, 45)
            }
        }
        .task(id: refreshTaskID) {
            guard scenePhase == .active, isActive else { return }

            // Entering Weather immediately refreshes only when the stored forecast is stale.
            await viewModel.refresh(force: viewModel.weather == nil)

            guard !Task.isCancelled, scenePhase == .active, isActive else { return }
            await autoRefreshLoop()
        }
    }

    private var refreshTaskID: String {
        "\(scenePhase == .active ? "active" : "inactive")-\(isActive ? "visible" : "hidden")"
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WEATHER")
                    .font(.system(size: 54, weight: .black, design: .rounded))
                Text("Current conditions and forecast")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(viewModel.errorMessage == nil ? "Auto refresh · ~15 min" : "Retrying · ~2 min")
                    .font(.caption.bold())
                    .foregroundStyle(viewModel.errorMessage == nil ? .secondary : .orange)
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
        HStack(spacing: 16) {
            ForEach(WeatherLocation.presets) { location in
                Button {
                    Task { await viewModel.select(location) }
                } label: {
                    VStack(spacing: 2) {
                        Text(location.name).fontWeight(.bold)
                        Text(location.subtitle).font(.caption)
                    }
                    .frame(minWidth: 210)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.location == location ? .white : .gray.opacity(0.35))
                .foregroundStyle(viewModel.location == location ? .black : .white)
            }
        }
    }

    private func currentConditions(_ weather: OpenMeteoResponse) -> some View {
        HStack(spacing: 38) {
            Image(systemName: WeatherCode.symbol(weather.current.weatherCode))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 108))
                .frame(width: 150)

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.location.name)
                    .font(.title2.bold())
                Text("\(Int(weather.current.temperature2m.rounded()))°")
                    .font(.system(size: 92, weight: .black, design: .rounded))
                Text(WeatherCode.description(weather.current.weatherCode))
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            metric(title: "Feels Like", value: "\(Int(weather.current.apparentTemperature.rounded()))°", symbol: "thermometer.medium")
            metric(title: "Humidity", value: "\(weather.current.relativeHumidity2m)%", symbol: "humidity.fill")
            metric(title: "Wind", value: "\(Int(weather.current.windSpeed10m.rounded())) mph", symbol: "wind")
        }
        .padding(34)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private func metric(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.bold())
        }
        .frame(minWidth: 180, alignment: .leading)
    }

    private func hourlyForecast(_ weather: OpenMeteoResponse) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Next 12 Hours")
                .font(.title2.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(hourlyIndices(weather), id: \.self) { index in
                        HourlyForecastCard(
                            time: hourLabel(weather.hourly.time[index], weather: weather),
                            temperature: Int(weather.hourly.temperature2m[index].rounded()),
                            precipitation: weather.hourly.precipitationProbability[index],
                            weatherCode: weather.hourly.weatherCode[index]
                        )
                    }
                }
                .padding(.vertical, 14)
            }
        }
    }

    private func dailyForecast(_ weather: OpenMeteoResponse) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("7-Day Forecast")
                .font(.title2.bold())

            HStack(spacing: 16) {
                ForEach(Array(0..<dailyCount(weather)), id: \.self) { index in
                    VStack(spacing: 12) {
                        Text(dayLabel(weather.daily.time[index], weather: weather))
                            .font(.headline)
                        Image(systemName: WeatherCode.symbol(weather.daily.weatherCode[index]))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 40))
                        HStack(spacing: 8) {
                            Text("\(Int(weather.daily.temperature2mMax[index].rounded()))°")
                                .fontWeight(.bold)
                            Text("\(Int(weather.daily.temperature2mMin[index].rounded()))°")
                                .foregroundStyle(.secondary)
                        }
                        Label("\(weather.daily.precipitationProbabilityMax[index])%", systemImage: "drop.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
        }
        .padding(.bottom, 45)
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

    private func hourLabel(_ isoLocal: String, weather: OpenMeteoResponse) -> String {
        let parser = localHourlyFormatter(for: weather)
        guard let date = parser.date(from: isoLocal) else { return isoLocal }

        let display = DateFormatter()
        display.locale = Locale(identifier: "en_US")
        display.timeZone = TimeZone(identifier: weather.timezone) ?? .current
        display.dateFormat = "h a"
        return display.string(from: date)
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

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text(time)
                .font(.headline)
            Image(systemName: WeatherCode.symbol(weatherCode))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 42))
            Text("\(temperature)°")
                .font(.title2.bold())
            Label("\(precipitation)%", systemImage: "drop.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 150, height: 190)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(isFocused ? 0.50 : 0.08), lineWidth: isFocused ? 3 : 1)
        }
        .scaleEffect(isFocused ? 1.06 : 1)
        .animation(.easeOut(duration: 0.12), value: isFocused)
        .focusable()
        .focused($isFocused)
        .zIndex(isFocused ? 1 : 0)
        .accessibilityLabel("\(time), \(temperature) degrees, \(WeatherCode.description(weatherCode)), \(precipitation) percent precipitation")
    }
}
