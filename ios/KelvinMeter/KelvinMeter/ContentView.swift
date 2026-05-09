import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MeterViewModel()
    @State private var isShowingDetails = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                CameraPreview(session: viewModel.cameraMeter.session)
                    .ignoresSafeArea(.container, edges: .all)

                LinearGradient(
                    colors: [.black.opacity(0.62), .clear, .black.opacity(0.38)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    Spacer(minLength: 22)

                    reticle

                    statusLine

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, proxy.safeAreaInsets.top + 10)
                .padding(.bottom, 186)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                bottomControls
                    .padding(.horizontal, 16)
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom + 42, 58))
            }
            .dynamicTypeSize(.xSmall ... .large)
            .background(Color(red: 17 / 255, green: 19 / 255, blue: 18 / 255))
            .ignoresSafeArea(.container, edges: .all)
            .persistentSystemOverlays(.hidden)
        }
        .task {
            viewModel.startCameraIfNeeded()
        }
        .sheet(isPresented: $isShowingDetails) {
            MeterDetailsSheet(viewModel: viewModel)
                .presentationDetents([.medium])
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("KELVIN METER")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))

            Text(viewModel.kelvinText)
                .font(.system(size: 76, weight: .heavy, design: .default))
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .foregroundStyle(viewModel.kelvinColor)
                .shadow(color: viewModel.kelvinGlow, radius: 24)
                .shadow(color: .black.opacity(0.38), radius: 18, y: 6)

            TemperatureRail(position: viewModel.temperaturePosition)
                .frame(width: 288, height: 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var reticle: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.76), lineWidth: 2)
                .shadow(color: .black.opacity(0.28), radius: 34, y: 16)

            Circle()
                .trim(from: 0.07, to: 0.27)
                .stroke(Color(red: 244 / 255, green: 179 / 255, blue: 95 / 255).opacity(0.9), lineWidth: 1)
                .rotationEffect(.degrees(-72))
                .padding(-8)

            Circle()
                .trim(from: 0.57, to: 0.77)
                .stroke(Color(red: 141 / 255, green: 183 / 255, blue: 255 / 255).opacity(0.85), lineWidth: 1)
                .rotationEffect(.degrees(-72))
                .padding(-8)

            Rectangle()
                .fill(.white.opacity(0.82))
                .frame(width: 92, height: 1)

            Rectangle()
                .fill(.white.opacity(0.82))
                .frame(width: 1, height: 92)
        }
        .frame(width: 190, height: 190)
    }

    private var statusLine: some View {
        Text(viewModel.measurementStateText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .padding(.top, 18)
            .shadow(color: .black.opacity(0.44), radius: 10, y: 3)
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            MetricsStrip(
                tint: viewModel.tintText,
                lux: viewModel.luxText,
                exposure: viewModel.evText
            )

            HStack(spacing: 10) {
                Button {
                    if viewModel.isCameraRunning {
                        viewModel.toggleHold()
                    } else {
                        viewModel.startCamera()
                    }
                } label: {
                    Text(viewModel.isCameraRunning ? (viewModel.isHeld ? "Resume" : "Hold") : "Start Camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryMeterButtonStyle())

                UtilityButton(systemImage: "sun.max", label: "Cal") {
                    viewModel.calibrateToDaylight()
                }
                .disabled(!viewModel.isCameraRunning)
                .contextMenu {
                    Button("Reset Calibration") {
                        viewModel.resetCalibration()
                    }
                }

                UtilityButton(
                    systemImage: viewModel.areCameraControlsLocked ? "lock.open" : "lock",
                    label: viewModel.areCameraControlsLocked ? "Unlock" : "Lock"
                ) {
                    viewModel.toggleCameraLock()
                }
                .disabled(!viewModel.isCameraRunning)

                UtilityButton(systemImage: "info.circle", label: "Info") {
                    isShowingDetails = true
                }
            }
        }
        .frame(maxWidth: 520)
    }
}

private struct MetricsStrip: View {
    let tint: String
    let lux: String
    let exposure: String

    var body: some View {
        HStack(spacing: 0) {
            MetricItem(label: "Tint", value: tint)
            Divider().overlay(.white.opacity(0.16))
            MetricItem(label: "Lux", value: lux)
            Divider().overlay(.white.opacity(0.16))
            MetricItem(label: "EV", value: exposure.replacingOccurrences(of: "EV ", with: ""))
        }
        .frame(height: 48)
        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.12))
        }
        .shadow(color: .black.opacity(0.16), radius: 10, y: 5)
    }
}

private struct MetricItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.58))
            Text(value)
                .font(.callout.weight(.bold))
                .fontDesign(.monospaced)
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MeterDetailsSheet: View {
    @ObservedObject var viewModel: MeterViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Reading") {
                    LabeledContent("White balance", value: viewModel.whiteBalanceText)
                    LabeledContent("Calibration", value: viewModel.calibrationStatus)
                    LabeledContent("Lux stats", value: viewModel.statsText)
                    LabeledContent("State", value: viewModel.measurementStateText)
                }

                Section("Calibration") {
                    Button("Calibrate to 5600K") {
                        viewModel.calibrateToDaylight()
                    }
                    .disabled(!viewModel.isCameraRunning)

                    Button("Reset Calibration", role: .destructive) {
                        viewModel.resetCalibration()
                    }
                }
            }
            .navigationTitle("Meter Details")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct UtilityButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white.opacity(0.88))
            .frame(width: 56, height: 48)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.16))
            }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private struct TemperatureRail: View {
    let position: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 244 / 255, green: 179 / 255, blue: 95 / 255),
                                Color(red: 244 / 255, green: 242 / 255, blue: 236 / 255),
                                Color(red: 141 / 255, green: 183 / 255, blue: 255 / 255)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 4)

                Circle()
                    .fill(Color(red: 244 / 255, green: 242 / 255, blue: 236 / 255))
                    .overlay {
                        Circle().stroke(.black.opacity(0.72), lineWidth: 2)
                    }
                    .frame(width: 12, height: 12)
                    .offset(x: max(0, min(geometry.size.width - 12, geometry.size.width * position - 6)))
                    .animation(.easeOut(duration: 0.22), value: position)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct PrimaryMeterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.bold))
            .foregroundStyle(Color(red: 16 / 255, green: 33 / 255, blue: 29 / 255))
            .frame(height: 48)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 142 / 255, green: 227 / 255, blue: 200 / 255),
                        Color(red: 244 / 255, green: 214 / 255, blue: 140 / 255)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .opacity(configuration.isPressed ? 0.84 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

#Preview {
    ContentView()
}
