import SwiftUI
import PhotosUI

// MARK: - Full-Bleed Live Camera Viewfinder with Vision & Barcode Scanning

public struct CameraViewfinderView: View {
    @Bindable var viewModel: ScannerViewModel
    @Binding var isSheetPresented: Bool
    @Binding var isProviderSettingsPresented: Bool
    @State private var scanLineOffset: CGFloat = -100

    private let reticleWidth: CGFloat = 280
    private let reticleHeight: CGFloat = 220
    private let reticleRadius: CGFloat = 24
    private let bracketInset: CGFloat = 6

    public init(
        viewModel: ScannerViewModel,
        isSheetPresented: Binding<Bool>,
        isProviderSettingsPresented: Binding<Bool> = .constant(false)
    ) {
        self.viewModel = viewModel
        self._isSheetPresented = isSheetPresented
        self._isProviderSettingsPresented = isProviderSettingsPresented
    }

    public var body: some View {
        ZStack {
            // 1. Live AVFoundation Camera Preview
            if viewModel.cameraService.isCameraAvailable {
                CameraPreviewView(
                    session: viewModel.cameraService.captureSession,
                    isCameraAvailable: true
                )
            } else {
                cameraBackdrop
            }

            // 2. Camera Viewfinder Framing & Reticle
            VStack(spacing: 16) {
                Spacer()

                // Guidance Text with Active Provider & Scan Status
                VStack(spacing: 4) {
                    Text("Point at Barcode or Nutrition Label")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)

                    HStack(spacing: 6) {
                        Image(systemName: viewModel.selectedProvider.systemImageName)
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(viewModel.selectedProvider.shortName) • \(viewModel.scanStatus)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.cyan)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.black.opacity(0.55), in: Capsule())

                // Concentric Scanning Window
                ZStack {
                    RoundedRectangle(cornerRadius: reticleRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        .frame(width: reticleWidth, height: reticleHeight)

                    ConcentricReticle(
                        outerRadius: reticleRadius,
                        inset: bracketInset,
                        armLength: 20
                    )
                    .stroke(
                        Color.white,
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: reticleWidth, height: reticleHeight)

                    // Animated Scanning Beam
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .cyan.opacity(0.85), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: reticleWidth - 16, height: 2)
                        .offset(y: scanLineOffset)
                        .onAppear {
                            withAnimation(
                                .easeInOut(duration: 2.0)
                                .repeatForever(autoreverses: true)
                            ) {
                                scanLineOffset = 100
                            }
                        }
                }

                // Barcode Readout Tag (when a barcode is active)
                if viewModel.selectedProduct.barcode != "––" {
                    Label(viewModel.selectedProduct.barcode, systemImage: "barcode.viewfinder")
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: Capsule())
                }

                Spacer()
                Spacer()
            }

            // 3. Top Floating Chrome (Flashlight, Photo Picker, Provider Switcher, Diet Selector)
            VStack {
                topControlBar
                    .padding(.horizontal, 16)
                    .padding(.top, 54)
                Spacer()
            }

            // 4. Bottom Floating Pill to restore sheet when dismissed
            VStack {
                Spacer()
                if !isSheetPresented {
                    restoreSheetButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 48)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isSheetPresented)
        .ignoresSafeArea()
    }

    // MARK: - Restore Sheet Floating Pill

    private var restoreSheetButton: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                isSheetPresented = true
            }
        } label: {
            HStack(spacing: 8) {
                if viewModel.errorMessage != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Evaluation Error")
                        .font(.subheadline.bold())
                        .lineLimit(1)
                } else if let decision = viewModel.decision, viewModel.selectedProduct.id != "waiting" {
                    Image(systemName: decision.isSafe ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(decision.isSafe ? .green : .red)
                    Text(viewModel.selectedProduct.name)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                } else {
                    Image(systemName: "chart.bar.doc.horizontal.fill")
                        .foregroundStyle(.cyan)
                    Text("View Nutrition Sheet")
                        .font(.subheadline.bold())
                }
                Image(systemName: "chevron.up")
                    .font(.caption2.bold())
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .accessibilityLabel(viewModel.selectedProduct.id != "waiting" ? "View nutrition and safety report for \(viewModel.selectedProduct.name)" : "Open nutrition and safety sheet")
    }

    // MARK: - Top Control Bar (Flashlight + Photos Picker + Provider Picker + Diet Selector)

    private var topControlBar: some View {
        HStack(spacing: 8) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    // Flashlight Toggle
                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        viewModel.toggleFlashlight()
                    } label: {
                        Image(systemName: viewModel.cameraService.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.body)
                            .foregroundStyle(viewModel.cameraService.isTorchOn ? .yellow : .primary)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(viewModel.cameraService.isTorchOn ? "Turn flashlight off" : "Turn flashlight on")

                    // Photos Library Scan Picker
                    PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Import photo of nutrition label from library")

                    // Provider Switcher & Settings Menu
                    Menu {
                        Picker("System One Provider", selection: $viewModel.selectedProvider) {
                            ForEach(NutritionScannerProvider.allCases) { provider in
                                Label(provider.displayName, systemImage: provider.systemImageName)
                                    .tag(provider)
                            }
                        }

                        Divider()

                        Button {
                            isProviderSettingsPresented = true
                        } label: {
                            Label("Configure Provider Credentials…", systemImage: "gearshape.fill")
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: viewModel.selectedProvider.systemImageName)
                                .font(.caption.bold())
                                .foregroundStyle(.cyan)
                            Text(viewModel.selectedProvider.shortName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel("Select System One provider, currently \(viewModel.selectedProvider.displayName)")
                }
            }

            Spacer(minLength: 4)

            // Diet Selector Dropdown Menu
            Menu {
                Picker("Dietary Profile", selection: $viewModel.selectedProfile) {
                    ForEach(DietaryProfile.allProfiles) { profile in
                        Label(profile.title, systemImage: profile.icon)
                            .tag(profile)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: viewModel.selectedProfile.icon)
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                    Text(viewModel.selectedProfile.shortName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Select dietary safety profile, currently \(viewModel.selectedProfile.title)")
        }
    }

    // MARK: - Camera Backdrop

    private var cameraBackdrop: some View {
        ZStack {
            Color.black

            RadialGradient(
                colors: [Color(white: 0.16), Color.black],
                center: .center,
                startRadius: 80,
                endRadius: 420
            )

            if viewModel.cameraService.isTorchOn {
                Color.white.opacity(0.18)
            }
        }
    }
}

// MARK: - Concentric Reticle Shape

private struct ConcentricReticle: Shape {
    let outerRadius: CGFloat
    let inset: CGFloat
    let armLength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let r = max(4, outerRadius - inset)
        let minX = rect.minX + inset
        let maxX = rect.maxX - inset
        let minY = rect.minY + inset
        let maxY = rect.maxY - inset

        // 1. Top-Left
        path.move(to: CGPoint(x: minX, y: minY + r + armLength))
        path.addLine(to: CGPoint(x: minX, y: minY + r))
        path.addRelativeArc(center: CGPoint(x: minX + r, y: minY + r), radius: r, startAngle: .degrees(180), delta: .degrees(90))
        path.addLine(to: CGPoint(x: minX + r + armLength, y: minY))

        // 2. Top-Right
        path.move(to: CGPoint(x: maxX - r - armLength, y: minY))
        path.addLine(to: CGPoint(x: maxX - r, y: minY))
        path.addRelativeArc(center: CGPoint(x: maxX - r, y: minY + r), radius: r, startAngle: .degrees(270), delta: .degrees(90))
        path.addLine(to: CGPoint(x: maxX, y: minY + r + armLength))

        // 3. Bottom-Right
        path.move(to: CGPoint(x: maxX, y: maxY - r - armLength))
        path.addLine(to: CGPoint(x: maxX, y: maxY - r))
        path.addRelativeArc(center: CGPoint(x: maxX - r, y: maxY - r), radius: r, startAngle: .degrees(0), delta: .degrees(90))
        path.addLine(to: CGPoint(x: maxX - r - armLength, y: maxY))

        // 4. Bottom-Left
        path.move(to: CGPoint(x: minX + r + armLength, y: maxY))
        path.addLine(to: CGPoint(x: minX + r, y: maxY))
        path.addRelativeArc(center: CGPoint(x: minX + r, y: maxY - r), radius: r, startAngle: .degrees(90), delta: .degrees(90))
        path.addLine(to: CGPoint(x: minX, y: maxY - r - armLength))

        return path
    }
}
