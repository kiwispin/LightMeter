import AVFoundation
import CoreImage
import SwiftUI

struct MeterReading: Sendable {
    let kelvin: Double
    let tint: Double
    let light: Double
    let lux: Double
    let footCandles: Double
    let ev100: Double
    let red: Double
    let green: Double
    let blue: Double
}

private struct ExposureSample: Sendable {
    let iso: Double
    let duration: Double
    let aperture: Double
}

final class CameraMeter: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.kiwispin.KelvinMeter.session")
    private let outputQueue = DispatchQueue(label: "com.kiwispin.KelvinMeter.output")
    private var device: AVCaptureDevice?

    var onReading: (@MainActor (MeterReading) -> Void)?
    var onMessage: (@MainActor (String) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                guard allowed else {
                    Task { @MainActor in self?.onMessage?("Camera permission was blocked.") }
                    return
                }

                self?.configureAndStart()
            }
        case .denied, .restricted:
            Task { @MainActor in onMessage?("Camera permission was blocked.") }
        @unknown default:
            Task { @MainActor in onMessage?("Camera permission is unavailable.") }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func lockCurrentCameraControls() {
        sessionQueue.async { [weak self] in
            guard let self, let device else { return }

            do {
                try device.lockForConfiguration()

                if device.isExposureModeSupported(.locked) {
                    device.exposureMode = .locked
                }

                if device.isWhiteBalanceModeSupported(.locked) {
                    device.whiteBalanceMode = .locked
                }

                if device.isFocusModeSupported(.locked) {
                    device.focusMode = .locked
                }

                device.unlockForConfiguration()
                Task { @MainActor in self.onMessage?("Camera exposure and white balance locked.") }
            } catch {
                Task { @MainActor in self.onMessage?("Could not lock camera controls.") }
            }
        }
    }

    func unlockCameraControls() {
        sessionQueue.async { [weak self] in
            guard let self, let device else { return }

            do {
                try device.lockForConfiguration()

                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }

                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }

                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }

                device.unlockForConfiguration()
                Task { @MainActor in self.onMessage?("Camera controls returned to auto.") }
            } catch {
                Task { @MainActor in self.onMessage?("Could not unlock camera controls.") }
            }
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if session.isRunning {
                return
            }

            if session.inputs.isEmpty {
                configureSession()
            }

            session.startRunning()
            Task { @MainActor in self.onMessage?("Metering from the center target.") }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input)
        else {
            Task { @MainActor in onMessage?("Back camera is unavailable.") }
            session.commitConfiguration()
            return
        }

        session.addInput(input)
        device = camera
        primeDevice(camera)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        videoOutput.connection(with: .video)?.videoRotationAngle = 90
        session.commitConfiguration()
    }

    private func primeDevice(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }

            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }

            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            device.unlockForConfiguration()
        } catch {
            Task { @MainActor in onMessage?("Could not configure camera controls.") }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            let reading = Self.readCenterPatch(from: pixelBuffer, exposure: currentExposureSample())
        else {
            return
        }

        Task { @MainActor in onReading?(reading) }
    }

    private func currentExposureSample() -> ExposureSample? {
        guard let device else {
            return nil
        }

        let duration = CMTimeGetSeconds(device.exposureDuration)
        guard duration > 0, device.iso > 0, device.lensAperture > 0 else {
            return nil
        }

        return ExposureSample(
            iso: Double(device.iso),
            duration: duration,
            aperture: Double(device.lensAperture)
        )
    }

    private static func readCenterPatch(from pixelBuffer: CVPixelBuffer, exposure: ExposureSample?) -> MeterReading? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let patchSize = max(20, Int(Double(min(width, height)) * 0.16))
        let startX = max(0, (width - patchSize) / 2)
        let startY = max(0, (height - patchSize) / 2)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)

        var samples: [(red: Double, green: Double, blue: Double, luminance: Double)] = []
        samples.reserveCapacity(patchSize * patchSize)

        let sampleStride = max(1, patchSize / 64)

        for y in stride(from: startY, to: startY + patchSize, by: sampleStride) {
            for x in stride(from: startX, to: startX + patchSize, by: sampleStride) {
                let offset = y * bytesPerRow + x * 4
                let blue = Double(bytes[offset])
                let green = Double(bytes[offset + 1])
                let red = Double(bytes[offset + 2])
                let maxChannel = max(red, green, blue)
                let minChannel = min(red, green, blue)
                let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue

                if luminance < 24 || luminance > 242 || maxChannel - minChannel > 115 {
                    continue
                }

                samples.append((red, green, blue, luminance))
            }
        }

        guard samples.count > 24 else {
            return nil
        }

        samples.sort { $0.luminance < $1.luminance }

        let trimStart = Int(Double(samples.count) * 0.12)
        let trimEnd = Int(Double(samples.count) * 0.88)
        let trimmed = Array(samples[trimStart..<max(trimStart + 1, trimEnd)])

        let total = trimmed.reduce((red: 0.0, green: 0.0, blue: 0.0)) { partial, sample in
            (
                red: partial.red + sample.red,
                green: partial.green + sample.green,
                blue: partial.blue + sample.blue
            )
        }

        let red = total.red / Double(trimmed.count)
        let green = total.green / Double(trimmed.count)
        let blue = total.blue / Double(trimmed.count)
        let kelvin = rgbToKelvin(red: red, green: green, blue: blue)
        let tint = clamp((((red + blue) / 2) - green) / 128 * 100, min: -100, max: 100)
        let light = clamp((0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255 * 100, min: 0, max: 100)
        let ev100 = estimateEV100(from: exposure)
        let lux = estimateLux(ev100: ev100, light: light)

        return MeterReading(
            kelvin: kelvin,
            tint: tint,
            light: light,
            lux: lux,
            footCandles: lux / 10.7639,
            ev100: ev100,
            red: red,
            green: green,
            blue: blue
        )
    }

    private static func estimateEV100(from exposure: ExposureSample?) -> Double {
        guard let exposure else {
            return 0
        }

        let ev = log2((exposure.aperture * exposure.aperture) / exposure.duration)
        return clamp(ev - log2(exposure.iso / 100), min: -8, max: 22)
    }

    private static func estimateLux(ev100: Double, light: Double) -> Double {
        guard ev100 > -8 else {
            return 0
        }

        let luminanceBias = clamp(light / 50, min: 0.35, max: 2.4)
        return clamp(2.5 * pow(2, ev100) * luminanceBias, min: 0, max: 200_000)
    }

    private static func rgbToKelvin(red: Double, green: Double, blue: Double) -> Double {
        let linearRed = srgbToLinear(red)
        let linearGreen = srgbToLinear(green)
        let linearBlue = srgbToLinear(blue)

        let xValue = linearRed * 0.4124564 + linearGreen * 0.3575761 + linearBlue * 0.1804375
        let yValue = linearRed * 0.2126729 + linearGreen * 0.7151522 + linearBlue * 0.072175
        let zValue = linearRed * 0.0193339 + linearGreen * 0.119192 + linearBlue * 0.9503041
        let total = xValue + yValue + zValue

        guard total > 0 else {
            return 0
        }

        let x = xValue / total
        let y = yValue / total
        let n = (x - 0.332) / (0.1858 - y)
        let cct = 449 * pow(n, 3) + 3525 * pow(n, 2) + 6823.3 * n + 5520.33

        return clamp(cct, min: 1_000, max: 40_000)
    }

    private static func srgbToLinear(_ value: Double) -> Double {
        let channel = value / 255
        return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
}

private func clamp(_ value: Double, min lowerBound: Double, max upperBound: Double) -> Double {
    Swift.min(upperBound, Swift.max(lowerBound, value))
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
