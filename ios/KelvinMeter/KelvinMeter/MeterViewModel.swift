import AVFoundation
import SwiftUI

enum CalibrationReference: String, CaseIterable, Identifiable {
    case daylight
    case tungsten
    case cloudy
    case shade
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daylight: "Daylight"
        case .tungsten: "Tungsten"
        case .cloudy: "Cloudy"
        case .shade: "Shade"
        case .custom: "Custom"
        }
    }

    var shortTitle: String {
        switch self {
        case .daylight: "D55"
        case .tungsten: "A"
        case .cloudy: "D65"
        case .shade: "Shade"
        case .custom: "Custom"
        }
    }

    func targetKelvin(customKelvin: Double) -> Double {
        switch self {
        case .daylight: 5_600
        case .tungsten: 3_200
        case .cloudy: 6_500
        case .shade: 7_500
        case .custom: customKelvin
        }
    }
}

private struct CalibrationProfile: Codable {
    let offset: Double
    let targetKelvin: Double
    let measuredKelvin: Double
    let sourceName: String
    let sampleCount: Int
    let spread: Double
    let confidence: String
    let createdAt: Date
}

@MainActor
final class MeterViewModel: ObservableObject {
    @Published var kelvinText = "-- K"
    @Published var rawKelvinText = "-- K"
    @Published var tintText = "--"
    @Published var luxText = "--"
    @Published var evText = "--"
    @Published var statsText = "Min --  Avg --  Max --"
    @Published var whiteBalanceText = "WB --"
    @Published var measurementStateText = "READY"
    @Published var message = "Use a white or grey target for the cleanest reading."
    @Published var calibrationStatus = "Cal off"
    @Published var calibrationDetailText = "No phone profile stored."
    @Published var calibrationCaptureText = "Choose a known reference, fill the reticle with a neutral card, then capture."
    @Published var calibrationProgress = 0.0
    @Published var readingConfidenceText = "ESTIMATE"
    @Published var isHeld = false
    @Published var isCameraRunning = false
    @Published var areCameraControlsLocked = false
    @Published var isCalibrating = false
    @Published var kelvinColor = Color(red: 244 / 255, green: 242 / 255, blue: 236 / 255)
    @Published var kelvinGlow = Color(red: 244 / 255, green: 242 / 255, blue: 236 / 255).opacity(0.34)
    @Published var temperaturePosition = 0.5

    let cameraMeter = CameraMeter()

    private let legacyCalibrationStorageKey = "kelvinMeterCalibrationOffset"
    private let calibrationProfileStorageKey = "kelvinMeterCalibrationProfileV1"
    private let calibrationSampleTarget = 54
    private var calibrationProfile: CalibrationProfile?
    private var calibrationOffset: Double
    private var calibrationSamples: [Double] = []
    private var calibrationLightSamples: [Double] = []
    private var activeCalibrationTarget = 5_600.0
    private var activeCalibrationSource = "Daylight"
    private var smoothKelvin = 0.0
    private var smoothTint = 0.0
    private var smoothLight = 0.0
    private var smoothLux = 0.0
    private var smoothEV = 0.0
    private var recentKelvinReadings: [Double] = []
    private var minLux = Double.infinity
    private var maxLux = 0.0
    private var totalLux = 0.0
    private var readingCount = 0

    init() {
        calibrationProfile = Self.loadCalibrationProfile(storageKey: calibrationProfileStorageKey)
        calibrationOffset = calibrationProfile?.offset ?? UserDefaults.standard.double(forKey: legacyCalibrationStorageKey)
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

        beginCalibration(reference: .daylight, customKelvin: 5_600)
    }

    func beginCalibration(reference: CalibrationReference, customKelvin: Double) {
        guard isCameraRunning, smoothKelvin > 0 else {
            message = "Start the camera and meter a neutral card first."
            calibrationCaptureText = "Camera needs a live neutral-card reading before calibration."
            return
        }

        isHeld = false
        activeCalibrationTarget = clamp(reference.targetKelvin(customKelvin: customKelvin), min: 1_000, max: 40_000)
        activeCalibrationSource = reference == .custom ? "Custom \(Int(activeCalibrationTarget))K" : reference.title
        calibrationSamples.removeAll(keepingCapacity: true)
        calibrationLightSamples.removeAll(keepingCapacity: true)
        calibrationProgress = 0
        isCalibrating = true
        calibrationCaptureText = "Capturing \(activeCalibrationSource) samples..."
        message = "Keep the neutral card steady in the reticle."
        updateMeasurementState()
    }

    func cancelCalibration() {
        isCalibrating = false
        calibrationSamples.removeAll()
        calibrationLightSamples.removeAll()
        calibrationProgress = 0
        calibrationCaptureText = "Calibration cancelled."
        updateMeasurementState()
    }

    func resetCalibration() {
        calibrationOffset = 0
        calibrationProfile = nil
        UserDefaults.standard.removeObject(forKey: calibrationProfileStorageKey)
        UserDefaults.standard.removeObject(forKey: legacyCalibrationStorageKey)
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

        rawKelvinText = "\(Int(round(smoothKelvin / 50) * 50)) K"
        updateRecentKelvinReadings(smoothKelvin)

        let calibratedKelvin = applyCalibration(smoothKelvin)
        kelvinText = "\(Int(round(calibratedKelvin / 50) * 50)) K"
        tintText = formatTint(smoothTint)
        luxText = formatLux(smoothLux)
        evText = String(format: "EV %.1f", smoothEV)
        whiteBalanceText = whiteBalancePreset(for: calibratedKelvin)
        temperaturePosition = Self.temperaturePosition(for: calibratedKelvin)
        setKelvinColor(for: calibratedKelvin)
        updateLuxStats(smoothLux)
        captureCalibrationSampleIfNeeded(reading: reading)
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
        if let calibrationProfile {
            calibrationStatus = "\(calibrationProfile.sourceName) \(formatSignedKelvin(calibrationOffset))"
            calibrationDetailText = "\(Int(calibrationProfile.targetKelvin))K target, \(Int(calibrationProfile.measuredKelvin))K measured, \(calibrationProfile.confidence.lowercased()) confidence."
        } else if calibrationOffset != 0 {
            calibrationStatus = "Legacy \(formatSignedKelvin(calibrationOffset))"
            calibrationDetailText = "Imported old single-offset calibration."
        } else {
            calibrationStatus = "Cal off"
            calibrationDetailText = "No phone profile stored."
        }
    }

    private func updateMeasurementState(for reading: MeterReading? = nil) {
        let mode: String

        if isCalibrating {
            mode = "CAL"
        } else if isHeld {
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
        updateReadingConfidence(for: reading)
        measurementStateText = "\(mode) · \(readingConfidenceText) · \(whiteBalanceText) · \(lockState)"
    }

    private func captureCalibrationSampleIfNeeded(reading: MeterReading) {
        guard isCalibrating else {
            return
        }

        guard reading.light >= 12, reading.light <= 88 else {
            calibrationCaptureText = reading.light < 12 ? "Too dark. Add light to the neutral card." : "Too bright. Avoid clipped highlights."
            return
        }

        calibrationSamples.append(smoothKelvin)
        calibrationLightSamples.append(reading.light)
        calibrationProgress = Double(calibrationSamples.count) / Double(calibrationSampleTarget)
        calibrationCaptureText = "Capturing \(activeCalibrationSource): \(calibrationSamples.count)/\(calibrationSampleTarget)"

        if calibrationSamples.count >= calibrationSampleTarget {
            finishCalibration()
        }
    }

    private func finishCalibration() {
        guard !calibrationSamples.isEmpty else {
            cancelCalibration()
            return
        }

        let average = calibrationSamples.reduce(0, +) / Double(calibrationSamples.count)
        let spread = standardDeviation(calibrationSamples)
        let averageLight = calibrationLightSamples.reduce(0, +) / Double(max(calibrationLightSamples.count, 1))
        let confidence: String

        if spread < 160, averageLight >= 22, averageLight <= 78 {
            confidence = "High"
        } else if spread < 320, averageLight >= 14, averageLight <= 86 {
            confidence = "Medium"
        } else {
            confidence = "Low"
        }

        calibrationOffset = (activeCalibrationTarget - average).rounded()
        calibrationProfile = CalibrationProfile(
            offset: calibrationOffset,
            targetKelvin: activeCalibrationTarget,
            measuredKelvin: average,
            sourceName: activeCalibrationSource,
            sampleCount: calibrationSamples.count,
            spread: spread,
            confidence: confidence,
            createdAt: Date()
        )
        Self.saveCalibrationProfile(calibrationProfile, storageKey: calibrationProfileStorageKey)
        UserDefaults.standard.removeObject(forKey: legacyCalibrationStorageKey)

        isCalibrating = false
        calibrationProgress = 1
        calibrationSamples.removeAll()
        calibrationLightSamples.removeAll()
        updateCalibrationStatus()
        calibrationCaptureText = "Saved \(activeCalibrationSource) profile with \(confidence.lowercased()) confidence."
        message = "Calibration saved: \(calibrationStatus)."
        updateMeasurementState()
    }

    private func updateRecentKelvinReadings(_ kelvin: Double) {
        recentKelvinReadings.append(kelvin)
        if recentKelvinReadings.count > 24 {
            recentKelvinReadings.removeFirst(recentKelvinReadings.count - 24)
        }
    }

    private func updateReadingConfidence(for reading: MeterReading?) {
        guard let reading else {
            readingConfidenceText = calibrationProfile == nil ? "ESTIMATE" : "CALIBRATED"
            return
        }

        if reading.light < 8 {
            readingConfidenceText = "LOW LIGHT"
        } else if reading.light > 92 {
            readingConfidenceText = "CLIPPED"
        } else if recentKelvinReadings.count >= 10, standardDeviation(recentKelvinReadings) > 420 {
            readingConfidenceText = "UNSTABLE"
        } else if calibrationProfile == nil {
            readingConfidenceText = "ESTIMATE"
        } else {
            readingConfidenceText = "CALIBRATED"
        }
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

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else {
            return 0
        }

        let average = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { partial, value in
            partial + pow(value - average, 2)
        } / Double(values.count)
        return sqrt(variance)
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

    private static func loadCalibrationProfile(storageKey: String) -> CalibrationProfile? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return nil
        }

        return try? JSONDecoder().decode(CalibrationProfile.self, from: data)
    }

    private static func saveCalibrationProfile(_ profile: CalibrationProfile?, storageKey: String) {
        guard let profile, let data = try? JSONEncoder().encode(profile) else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return
        }

        UserDefaults.standard.set(data, forKey: storageKey)
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
