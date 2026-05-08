import AVFoundation
import SwiftUI

@MainActor
final class MeterViewModel: ObservableObject {
    @Published var kelvinText = "-- K"
    @Published var tintText = "--"
    @Published var rgbText = "--"
    @Published var levelText = "--"
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

    init() {
        calibrationOffset = UserDefaults.standard.double(forKey: calibrationStorageKey)
        updateCalibrationStatus()

        cameraMeter.onReading = { [weak self] reading in
            self?.handle(reading)
        }
        cameraMeter.onMessage = { [weak self] message in
            self?.message = message
        }
    }

    func startCamera() {
        isCameraRunning = true
        message = "Starting camera..."
        cameraMeter.start()
    }

    func toggleHold() {
        isHeld.toggle()
        message = isHeld ? "Reading held." : "Metering from the center target."
    }

    func toggleCameraLock() {
        areCameraControlsLocked.toggle()

        if areCameraControlsLocked {
            cameraMeter.lockCurrentCameraControls()
        } else {
            cameraMeter.unlockCameraControls()
        }
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
    }

    func resetCalibration() {
        calibrationOffset = 0
        UserDefaults.standard.removeObject(forKey: calibrationStorageKey)
        updateCalibrationStatus()
        message = "Calibration cleared."
    }

    private func handle(_ reading: MeterReading) {
        guard !isHeld else {
            return
        }

        smoothKelvin = smoothKelvin == 0 ? reading.kelvin : smooth(smoothKelvin, reading.kelvin, amount: 0.16)
        smoothTint = smooth(smoothTint, reading.tint, amount: 0.18)
        smoothLight = smoothLight == 0 ? reading.light : smooth(smoothLight, reading.light, amount: 0.18)

        let calibratedKelvin = applyCalibration(smoothKelvin)
        kelvinText = "\(Int(round(calibratedKelvin / 50) * 50)) K"
        tintText = formatTint(smoothTint)
        rgbText = "\(Int(reading.red.rounded())) \(Int(reading.green.rounded())) \(Int(reading.blue.rounded()))"
        levelText = "\(Int(smoothLight.rounded()))%"
        temperaturePosition = Self.temperaturePosition(for: calibratedKelvin)
        setKelvinColor(for: calibratedKelvin)
    }

    private func applyCalibration(_ kelvin: Double) -> Double {
        clamp(kelvin + calibrationOffset, min: 1_000, max: 40_000)
    }

    private func updateCalibrationStatus() {
        calibrationStatus = calibrationOffset == 0 ? "Cal off" : "Cal \(formatSignedKelvin(calibrationOffset))"
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
