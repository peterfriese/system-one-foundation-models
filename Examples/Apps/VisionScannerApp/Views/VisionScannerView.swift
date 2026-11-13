import SwiftUI
import CoreGraphics
import UniformTypeIdentifiers
import FoundationModels
import SystemOneCore
import ClefFoundationModels
import OpenAIFoundationModels
import GeminiFoundationModels

// MARK: - Multi-Provider System One Vision Scanner Screen

public struct VisionScannerView: View {
    @AppStorage("cloudflareAccountID") private var storedAccountID: String = ""
    @AppStorage("cloudflareGatewayID") private var storedGatewayID: String = ""
    @KeychainStorage("cloudflareAPIToken") private var storedCloudflareToken: String = ""
    @AppStorage("localRunnerURL") private var storedLocalRunnerURL: String = "http://127.0.0.1:8000"
    @KeychainStorage("openAIAPIKey") private var storedOpenAIKey: String = ""
    @KeychainStorage("geminiAPIKey") private var storedGeminiKey: String = ""
    @AppStorage("systemOneProxyURL") private var storedProxyURL: String = ""
    @AppStorage("systemOneProxyModelID") private var storedProxyModelID: String = "systemone-default"
    @KeychainStorage("systemOneProxyBearerToken") private var storedProxyBearerToken: String = ""
    @KeychainStorage("firebaseAppCheckToken") private var storedAppCheckToken: String = ""

    @State private var cameraManager = CameraManager()
    @State private var selectedBackend: InspectionBackendSelection = InspectionBackendSelection.autoDetectedDefault
    @State private var isAutoScanEnabled: Bool = false
    @State private var isInspecting: Bool = false
    @State private var isSettingsPresented: Bool = false
    @State private var isFileImporterPresented: Bool = false
    @State private var currentResult: VisualInspectionResult?
    @State private var errorMessage: String?
    @State private var autoScanTask: Task<Void, Never>?
    @State private var inspectionTask: Task<Void, Never>?

    public init() {}

    public var body: some View {
        ZStack {
            // Background Live Hardware Camera or Imported Real Photo
            CameraPreviewView(
                cameraManager: cameraManager,
                isFileImporterPresented: $isFileImporterPresented
            )
            .ignoresSafeArea()

            // Viewfinder Reticle Target Box (only when live camera or imported image is active)
            if cameraManager.hasInspectableInput {
                ViewfinderReticle(isInspecting: isInspecting)
            }

            // Top Bar & Bottom HUD Overlay
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System One Vision Scanner")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Clef • OpenAI Luna • Gemini Decision • Proxy")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer()

                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Image(systemName: "photo.badge.plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Import Image File")

                    #if os(iOS)
                    if cameraManager.isCameraAvailable {
                        Button {
                            cameraManager.toggleTorch()
                        } label: {
                            Image(systemName: cameraManager.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                                .font(.headline)
                                .foregroundStyle(cameraManager.isTorchOn ? .yellow : .white)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel("Toggle Flashlight")
                    }
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
                        triggerManualInspection()
                    },
                    onOpenSettings: {
                        isSettingsPresented = true
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsSheetView()
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let first = urls.first {
                    if cameraManager.importPhotoFile(at: first) {
                        errorMessage = nil
                    } else {
                        errorMessage = cameraManager.errorMessage
                    }
                }
            case .failure(let error):
                errorMessage = "Failed to import photo: \(error.localizedDescription)"
            }
        }
        .task {
            await cameraManager.configure()
            cameraManager.start()
        }
        .onDisappear {
            cameraManager.stop()
            autoScanTask?.cancel()
            autoScanTask = nil
            inspectionTask?.cancel()
            inspectionTask = nil
        }
        .onChange(of: selectedBackend) { _, _ in
            errorMessage = nil
            // When comparing vision backends on an already-imported photo (with an active result),
            // automatically re-evaluate the exact same photo against the newly selected provider.
            if cameraManager.importedImage != nil && currentResult != nil && !isAutoScanEnabled {
                triggerManualInspection()
            }
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

    // MARK: - Visual Inspection Pipeline

    private func triggerManualInspection() {
        inspectionTask?.cancel()
        inspectionTask = Task {
            await performInspection()
        }
    }

    private func performInspection() async {
        guard !isInspecting else { return }

        guard cameraManager.hasInspectableInput else {
            isAutoScanEnabled = false
            errorMessage = "No camera or imported photo available. Tap 'Import Photo…' or 'Choose File…' to load a real image."
            return
        }

        let activeBackend = selectedBackend

        // 1. Fail-fast credential / endpoint resolution (Principle 7: zero empty-key fallbacks, zero mocks)
        let resolvedModel: any LanguageModel
        do {
            resolvedModel = try activeBackend.resolveLanguageModel(
                accountID: storedAccountID,
                gatewayID: storedGatewayID,
                cloudflareAPIToken: storedCloudflareToken,
                localRunnerURL: storedLocalRunnerURL,
                openAIAPIKey: storedOpenAIKey,
                geminiAPIKey: storedGeminiKey,
                proxyURLString: storedProxyURL,
                proxyBearerToken: storedProxyBearerToken,
                appCheckToken: storedAppCheckToken,
                proxyModelID: storedProxyModelID
            )
        } catch {
            isAutoScanEnabled = false
            errorMessage = error.localizedDescription
            return
        }

        isInspecting = true
        errorMessage = nil
        defer { isInspecting = false }

        // 2. Capture on-demand visual frame or imported real image
        guard let cgImage = await cameraManager.captureFrame() else {
            errorMessage = cameraManager.errorMessage ?? "No camera frame available to inspect."
            return
        }

        // 3. Build multimodal prompt with Apple Foundation Models Attachment
        let attachment = Attachment(cgImage)
        let prompt = Prompt {
            "Analyze the item in this camera viewfinder frame for identification, categorization, physical condition, and safety compliance."
            attachment
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let response = try await evaluateInspection(using: resolvedModel, prompt: prompt)
            try Task.checkCancellation()

            let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85)

            let result = VisualInspectionResult(
                decision: response.content,
                conditionScoreValue: response.conditionScoreValue,
                recognizedJudgement: response.recognizedJudgement(policy: policy),
                safetyJudgement: response.safetyJudgement(policy: policy),
                categoryDecision: response.categoryDecision(policy: policy),
                categoryConfidence: response.categoryConfidence,
                providerBadge: activeBackend.shortBadge,
                serverDurationMs: response.serverDurationMs,
                transportDurationMs: response.transportDurationMs,
                totalDurationMs: durationMs
            )

            self.currentResult = result
            self.errorMessage = nil
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch let error as SystemOneError {
            self.isAutoScanEnabled = false
            self.errorMessage = error.localizedDescription
        } catch {
            self.isAutoScanEnabled = false
            self.errorMessage = "Inspection failed (\(activeBackend.shortBadge)): \(error.localizedDescription)"
        }
    }

    private func evaluateInspection(
        using model: some LanguageModel,
        prompt: Prompt
    ) async throws -> LanguageModelSession.Response<VisualInspectionDecision> {
        let session = LanguageModelSession(model: model)
        return try await session.respond(
            to: prompt,
            generating: VisualInspectionDecision.self
        )
    }

    private func startAutoScanLoop() {
        autoScanTask?.cancel()
        autoScanTask = Task {
            while isAutoScanEnabled && !Task.isCancelled {
                await performInspection()
                guard isAutoScanEnabled && !Task.isCancelled else { break }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
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
