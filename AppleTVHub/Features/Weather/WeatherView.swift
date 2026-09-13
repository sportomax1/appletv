import SwiftUI

struct WeatherView: View {
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
        .task {
            if viewModel.weather == nil {
                await viewModel.refresh()
            }
        }
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

            if let updated = viewModel.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
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
                        VStack(spacing: 12) {
                            Text(hourLabel(weather.hourly.time[index]))
                                .font(.headline)
                            Image(systemName: WeatherCode.symbol(weather.hourly.weatherCode[index]))
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 42))
                            Text("\(Int(weather.hourly.temperature2m[index].rounded()))°")
                                .font(.title2.bold())
                            Label("\(weather.hourly.precipitationProbability[index])%", systemImage: "drop.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(20)
                        .frame(width: 150, height: 190)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func dailyForecast(_ weather: OpenMeteoResponse) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("7-Day Forecast")
                .font(.title2.bold())

            HStack(spacing: 16) {
                ForEach(Array(weather.daily.time.indices.prefix(7)), id: \.self) { index in
                    VStack(spacing: 12) {
                        Text(dayLabel(weather.daily.time[index]))
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
                Task { await viewModel.refresh() }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 350)
    }

    private func hourlyIndices(_ weather: OpenMeteoResponse) -> [Int] {
        let nowHour = Calendar.current.component(.hour, from: Date())
        let start = min(max(nowHour, 0), max(weather.hourly.time.count - 1, 0))
        let end = min(start + 12, weather.hourly.time.count)
        return start < end ? Array(start..<end) : []
    }

    private func hourLabel(_ isoLocal: String) -> String {
        guard isoLocal.count >= 13 else { return isoLocal }
        let hour = Int(isoLocal.dropFirst(11).prefix(2)) ?? 0
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }

    private func dayLabel(_ date: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let parsed = formatter.date(from: date) else { return date }
        return DateFormatter.weekdayShort.string(from: parsed)
    }
}
