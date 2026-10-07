import SwiftUI
import CoreGraphics
import FoundationModels
import SystemOneCore
import ClefFoundationModels

// MARK: - Clef Camera Scanner Screen

public struct ClefCameraScannerView: View {
    @AppStorage("cloudflareAccountID") private var storedAccountID: String = ""
    @AppStorage("cloudflareAPIToken") private var storedAPIToken: String = ""
    @AppStorage("localRunnerURL") private var storedLocalRunnerURL: String = "http://127.0.0.1:8000"

    @State private var cameraManager = CameraManager()
    @State private var selectedBackend: InspectionBackendSelection = .workersAIFlash
    @State private var isAutoScanEnabled: Bool = false
    @State private var isInspecting: Bool = false
    @State private var isSettingsPresented: Bool = false
    @State private var currentResult: VisualInspectionResult?
    @State private var errorMessage: String?
    @State private var autoScanTask: Task<Void, Never>?

    public init() {}

    public var body: some View {
        ZStack {
            // Background Live/Simulated Camera Viewfinder
            CameraPreviewView(cameraManager: cameraManager)
                .ignoresSafeArea()

            // Viewfinder Reticle Target Box
            ViewfinderReticle(isInspecting: isInspecting)

            // Top Bar Overlay
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clef Camera Scanner")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("System One Multimodal Foundation Models")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    #if os(iOS)
                    Button {
                        cameraManager.toggleTorch()
                    } label: {
                        Image(systemName: cameraManager.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.headline)
                            .foregroundStyle(cameraManager.isTorchOn ? .yellow : .white)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Toggle Flashlight")
                    #endif

                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Settings")
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                Spacer()

                // Bottom Liquid Glass HUD
                InspectionHUDView(
                    result: currentResult,
                    isInspecting: isInspecting,
                    errorMessage: errorMessage,
                    selectedBackend: $selectedBackend,
                    isAutoScanEnabled: $isAutoScanEnabled,
                    onInspectTapped: {
                        Task { await performInspection() }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsSheetView()
        }
        .task {
            await cameraManager.configure()
            cameraManager.start()
        }
        .onDisappear {
            cameraManager.stop()
            autoScanTask?.cancel()
            autoScanTask = nil
        }
        .onChange(of: isAutoScanEnabled) { _, newValue in
            if newValue {
                startAutoScanLoop()
            } else {
                autoScanTask?.cancel()
                autoScanTask = nil
            }
        }
    }

    // MARK: - Credential Resolution

    private var effectiveAccountID: String {
        let trimmed = storedAccountID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return ProcessInfo.processInfo.environment["CLOUDFLARE_ACCOUNT_ID"] ?? ""
    }

    private var effectiveAPIToken: String {
        let trimmed = storedAPIToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return ProcessInfo.processInfo.environment["CLOUDFLARE_API_TOKEN"] ?? ""
    }

    private var effectiveLocalRunnerURL: String {
        let trimmed = storedLocalRunnerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return ProcessInfo.processInfo.environment["LOCAL_RUNNER_URL"] ?? "http://127.0.0.1:8000"
    }

    // MARK: - Visual Inspection Pipeline

    private func performInspection() async {
        guard !isInspecting else { return }
        isInspecting = true
        errorMessage = nil

        defer { isInspecting = false }

        // 1. Capture visual frame
        guard let cgImage = await cameraManager.captureFrame() else {
            errorMessage = "No camera frame available to inspect."
            return
        }

        // 2. Validate credentials for Workers AI if selected
        let targetEndpoint = selectedBackend.endpoint(
            accountID: effectiveAccountID,
            localRunnerURL: effectiveLocalRunnerURL
        )

        if case .workersAI = targetEndpoint {
            if effectiveAccountID.isEmpty || effectiveAPIToken.isEmpty {
                errorMessage = "Cloudflare Workers AI requires Account ID and API Token. Tap Settings (gear icon) or set environment variables."
                return
            }
        }

        // 3. Configure Clef model and session using saved settings
        let clefModel = selectedBackend.makeModel(
            accountID: effectiveAccountID,
            apiToken: effectiveAPIToken,
            localRunnerURL: effectiveLocalRunnerURL
        )
        let session = LanguageModelSession(model: clefModel)

        // 4. Build multimodal prompt with Attachment
        let attachment = Attachment(cgImage)
        let prompt = Prompt {
            "Analyze the item in this camera viewfinder frame for identification, categorization, physical condition, and safety compliance."
            attachment
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let response = try await session.respond(
                to: prompt,
                generating: VisualInspectionDecision.self
            )

            let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85)

            let result = VisualInspectionResult(
                decision: response.content,
                conditionScoreValue: response.conditionScoreValue,
                recognizedJudgement: response.recognizedJudgement(policy: policy),
                safetyJudgement: response.safetyJudgement(policy: policy),
                categoryDecision: response.categoryDecision(policy: policy),
                categoryConfidence: response.categoryConfidence,
                serverDurationMs: response.serverDurationMs,
                transportDurationMs: response.transportDurationMs,
                totalDurationMs: durationMs
            )

            self.currentResult = result
            self.errorMessage = nil

        } catch let error as SystemOneError {
            self.errorMessage = error.localizedDescription
        } catch {
            self.errorMessage = "Inspection failed: \(error.localizedDescription)"
        }
    }

    private func startAutoScanLoop() {
        autoScanTask?.cancel()
        autoScanTask = Task {
            while isAutoScanEnabled && !Task.isCancelled {
                await performInspection()
                try? await Task.sleep(nanoseconds: 1_800_000_000) // 1.8s between auto inspections
            }
        }
    }
}

// MARK: - Viewfinder Reticle

private struct ViewfinderReticle: View {
    let isInspecting: Bool

    var body: some View {
        GeometryReader { geometry in
            let boxSize = min(geometry.size.width * 0.70, geometry.size.height * 0.45)
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isInspecting ? Color.cyan : Color.white.opacity(0.4),
                        style: StrokeStyle(lineWidth: isInspecting ? 3 : 2, dash: [10, 6])
                    )
                    .frame(width: boxSize, height: boxSize)
                    .scaleEffect(isInspecting ? 1.02 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isInspecting)

                // Corner Brackets
                CornerBrackets(size: boxSize)
                    .stroke(isInspecting ? Color.cyan : Color.white, lineWidth: 3)
                    .frame(width: boxSize, height: boxSize)
            }
            .position(x: geometry.size.width / 2, y: geometry.size.height * 0.42)
        }
    }
}

private struct CornerBrackets: Shape {
    let size: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arm: CGFloat = 24

        // Top Left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))

        // Top Right
        path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))

        // Bottom Right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))

        // Bottom Left
        path.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))

        return path
    }
}
