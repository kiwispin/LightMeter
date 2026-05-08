import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MeterViewModel()

    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.cameraMeter.session)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.82), .clear, .black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Spacer(minLength: 10)

                reticle

                Spacer(minLength: 10)

                bottomPanel
            }
            .padding(.horizontal, 16)
            .safeAreaPadding(.top, 10)
            .safeAreaPadding(.bottom, 10)
            .dynamicTypeSize(.xSmall ... .large)
        }
        .background(Color(red: 17 / 255, green: 19 / 255, blue: 18 / 255))
        .task {
            viewModel.startCameraIfNeeded()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("KELVIN METER")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))

            Text(viewModel.kelvinText)
                .font(.system(size: 64, weight: .heavy, design: .default))
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

    private var bottomPanel: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                ReadoutTile(label: "Tint", value: viewModel.tintText)
                ReadoutTile(label: "RGB", value: viewModel.rgbText)
                ReadoutTile(label: "Light", value: viewModel.levelText)
            }

            HStack(spacing: 8) {
                Button {
                    if viewModel.isCameraRunning {
                        viewModel.toggleHold()
                    } else {
                        viewModel.startCamera()
                    }
                } label: {
                    Text(viewModel.isCameraRunning ? (viewModel.isHeld ? "Live" : "Hold") : "Start camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryMeterButtonStyle())

                Button("Cal 5600") {
                    viewModel.calibrateToDaylight()
                }
                .buttonStyle(CompactMeterButtonStyle())
                .disabled(!viewModel.isCameraRunning)

                Button("Reset") {
                    viewModel.resetCalibration()
                }
                .buttonStyle(CompactMeterButtonStyle())
            }

            HStack(alignment: .top, spacing: 8) {
                Button(viewModel.areCameraControlsLocked ? "Unlock camera" : "Lock camera") {
                    viewModel.toggleCameraLock()
                }
                .buttonStyle(CompactMeterButtonStyle())
                .disabled(!viewModel.isCameraRunning)

                Text(viewModel.message)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(viewModel.calibrationStatus)
                .font(.caption.weight(.medium))
                .fontDesign(.monospaced)
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.18))
                }
        }
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

private struct ReadoutTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.64))

            Text(value)
                .font(.body.weight(.bold))
                .fontDesign(.monospaced)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(.white.opacity(0.11))
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

private struct SecondaryMeterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.bold))
            .foregroundStyle(.white.opacity(0.86))
            .frame(height: 48)
            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.16))
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

private struct CompactMeterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(.white.opacity(0.16))
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

#Preview {
    ContentView()
}
