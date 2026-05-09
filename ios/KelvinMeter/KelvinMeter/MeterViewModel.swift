import AVFoundation
import SwiftUI

@MainActor
final class MeterViewModel: ObservableObject {
    @Published var kelvinText = "-- K"
    @Published var tintText = "--"
    @Published var luxText = "--"
    @Published var evText = "--"
    @Published var statsText = "Min --  Avg --  Max --"
    @Published var whiteBalanceText = "WB --"
    @Published var measurementStateText = "READY"
    @Published var message = "Use a white or grey target for the cleanest reading."
    @Published var calibrationStatus = "Cal off"
    @Published var isHeld = false
    @Published var isCameraRunning = false
    @Published var areCameraControlsLocked = false
    @Published var kelvinColor = Color(red: 244 / 255, green: 242 / 255, blue: 236 / 255)
    @Published var kelvinGlow = Color(red: 244 / 255, green: 242 / 255, blue: 236 / 255).opacity(0.34)
    @Published var temperaturePosition = 0.5

    let cameraMeter = CameraMeter()

    private let calibrationTarget = 5_600.0
    private let calibrationStorageKey = "kelvinMeterCalibrationOffset"
    private var calibrationOffset: Double
    private var smoothKelvin = 0.0
    private var smoothTint = 0.0
    private var smoothLight = 0.0
    private var smoothLux = 0.0
    private var smoothEV = 0.0
    private var minLux = Double.infinity
    private var maxLux = 0.0
    private var totalLux = 0.0
    private var readingCount = 0

    init() {
        calibrationOffset = UserDefaults.standard.double(forKey: calibrationStorageKey)
        updateCalibrationStatus()
        updateMeasurementState()

        cameraMeter.onReading = { [weak self] reading in
            self?.handle(reading)
        }
        cameraMeter.onMessage = { [weak self] message in
            self?.handleMessage(message)
        }
    }

    func startCamera() {
        guard !isCameraRunning else {
            return
        }

        isCameraRunning = true
        message = "Starting camera..."
        measurementStateText = "STARTING"
        cameraMeter.start()
    }

    func startCameraIfNeeded() {
        startCamera()
    }

    func toggleHold() {
        isHeld.toggle()
        message = isHeld ? "Reading held." : "Metering from the center target."
        updateMeasurementState()
    }

    func toggleCameraLock() {
        areCameraControlsLocked.toggle()

        if areCameraControlsLocked {
            cameraMeter.lockCurrentCameraControls()
        } else {
            cameraMeter.unlockCameraControls()
        }

        updateMeasurementState()
    }

    func calibrateToDaylight() {
        guard smoothKelvin > 0 else {
            message = "Start the camera and meter a neutral card first."
            return
        }

        calibrationOffset = (calibrationTarget - smoothKelvin).rounded()
        UserDefaults.standard.set(calibrationOffset, forKey: calibrationStorageKey)
        updateCalibrationStatus()
        message = "Calibration set to 5600K."
        updateMeasurementState()
    }

    func resetCalibration() {
        calibrationOffset = 0
        UserDefaults.standard.removeObject(forKey: calibrationStorageKey)
        updateCalibrationStatus()
        message = "Calibration cleared."
        updateMeasurementState()
    }

    private func handle(_ reading: MeterReading) {
        guard !isHeld else {
            return
        }

        smoothKelvin = smoothKelvin == 0 ? reading.kelvin : smooth(smoothKelvin, reading.kelvin, amount: 0.16)
        smoothTint = smooth(smoothTint, reading.tint, amount: 0.18)
        smoothLight = smoothLight == 0 ? reading.light : smooth(smoothLight, reading.light, amount: 0.18)
        smoothLux = smoothLux == 0 ? reading.lux : smooth(smoothLux, reading.lux, amount: 0.18)
        smoothEV = smoothEV == 0 ? reading.ev100 : smooth(smoothEV, reading.ev100, amount: 0.18)

        let calibratedKelvin = applyCalibration(smoothKelvin)
        kelvinText = "\(Int(round(calibratedKelvin / 50) * 50)) K"
        tintText = formatTint(smoothTint)
        luxText = formatLux(smoothLux)
        evText = String(format: "EV %.1f", smoothEV)
        whiteBalanceText = whiteBalancePreset(for: calibratedKelvin)
        temperaturePosition = Self.temperaturePosition(for: calibratedKelvin)
        setKelvinColor(for: calibratedKelvin)
        updateLuxStats(smoothLux)
        updateMeasurementState(for: reading)

    }

    private func handleMessage(_ nextMessage: String) {
        message = nextMessage
        if nextMessage.contains("blocked") {
            measurementStateText = "CAMERA BLOCKED"
        } else if nextMessage.contains("unavailable") {
            measurementStateText = "NO CAMERA"
        } else {
            updateMeasurementState()
        }
    }

    private func applyCalibration(_ kelvin: Double) -> Double {
        clamp(kelvin + calibrationOffset, min: 1_000, max: 40_000)
    }

    private func updateCalibrationStatus() {
        calibrationStatus = calibrationOffset == 0 ? "Cal off" : "Cal \(formatSignedKelvin(calibrationOffset))"
    }

    private func updateMeasurementState(for reading: MeterReading? = nil) {
        let mode: String

        if isHeld {
            mode = "HELD"
        } else if !isCameraRunning {
            mode = "READY"
        } else if let reading, reading.light < 8 {
            mode = "LOW LIGHT"
        } else if let reading, reading.light > 92 {
            mode = "CLIPPED"
        } else {
            mode = "LIVE"
        }

        let lockState = areCameraControlsLocked ? "LOCKED" : "AUTO"
        measurementStateText = "\(mode) · \(whiteBalanceText) · \(calibrationStatus) · \(lockState)"
    }

    private func updateLuxStats(_ lux: Double) {
        guard lux > 0 else {
            return
        }

        minLux = min(minLux, lux)
        maxLux = max(maxLux, lux)
        totalLux += lux
        readingCount += 1

        let average = totalLux / Double(readingCount)
        statsText = "Min \(formatCompactLux(minLux))  Avg \(formatCompactLux(average))  Max \(formatCompactLux(maxLux))"
    }

    private func formatLux(_ lux: Double) -> String {
        if lux >= 10_000 {
            return "\(Int((lux / 100).rounded() * 100)) lx"
        }

        if lux >= 1_000 {
            return "\(Int((lux / 10).rounded() * 10)) lx"
        }

        return "\(Int(lux.rounded())) lx"
    }

    private func formatCompactLux(_ lux: Double) -> String {
        if lux >= 10_000 {
            return "\(Int((lux / 1_000).rounded()))k"
        }

        if lux >= 1_000 {
            return String(format: "%.1fk", lux / 1_000)
        }

        return "\(Int(lux.rounded()))"
    }

    private func formatTint(_ tint: Double) -> String {
        if abs(tint) < 4 {
            return "Neutral"
        }

        return tint > 0 ? "+\(Int(tint.rounded())) M" : "\(Int(abs(tint).rounded())) G"
    }

    private func formatSignedKelvin(_ kelvin: Double) -> String {
        kelvin > 0 ? "+\(Int(kelvin))K" : "\(Int(kelvin))K"
    }

    private func whiteBalancePreset(for kelvin: Double) -> String {
        switch kelvin {
        case ..<2_900:
            return "WB Tungsten"
        case ..<3_900:
            return "WB 3200K"
        case ..<4_900:
            return "WB Fluoro"
        case ..<6_300:
            return "WB Daylight"
        case ..<7_800:
            return "WB Cloudy"
        default:
            return "WB Shade"
        }
    }

    private func setKelvinColor(for kelvin: Double) {
        let position = Self.temperaturePosition(for: kelvin)
        let color: RGBColor

        if position < 0.48 {
            color = RGBColor.mix(.warm, .neutral, amount: position / 0.48)
        } else {
            color = RGBColor.mix(.neutral, .cool, amount: (position - 0.48) / 0.52)
        }

        kelvinColor = color.swiftUIColor
        kelvinGlow = color.swiftUIColor.opacity(0.38)
    }

    private func smooth(_ current: Double, _ next: Double, amount: Double) -> Double {
        current + (next - current) * amount
    }

    static func temperaturePosition(for kelvin: Double) -> Double {
        let minValue = log(2_000.0)
        let maxValue = log(12_000.0)
        let value = (log(clamp(kelvin, min: 2_000, max: 12_000)) - minValue) / (maxValue - minValue)
        return clamp(value, min: 0, max: 1)
    }
}

private struct RGBColor {
    static let warm = RGBColor(red: 244, green: 179, blue: 95)
    static let neutral = RGBColor(red: 244, green: 242, blue: 236)
    static let cool = RGBColor(red: 141, green: 183, blue: 255)

    let red: Double
    let green: Double
    let blue: Double

    var swiftUIColor: Color {
        Color(red: red / 255, green: green / 255, blue: blue / 255)
    }

    static func mix(_ start: RGBColor, _ end: RGBColor, amount: Double) -> RGBColor {
        let value = clamp(amount, min: 0, max: 1)
        return RGBColor(
            red: start.red + (end.red - start.red) * value,
            green: start.green + (end.green - start.green) * value,
            blue: start.blue + (end.blue - start.blue) * value
        )
    }
}

private func clamp(_ value: Double, min lowerBound: Double, max upperBound: Double) -> Double {
    Swift.min(upperBound, Swift.max(lowerBound, value))
}
