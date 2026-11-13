import SwiftUI
import Foundation
import CoreGraphics
import PhotosUI
import Observation
import FoundationModels
import SystemOneCore

// MARK: - Main Actor Scanner View Model (Camera + Vision + Multi-Provider System One)

@MainActor
@Observable
public final class ScannerViewModel {
    public var selectedProvider: NutritionScannerProvider {
        didSet {
            guard selectedProvider != oldValue else { return }
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: "selectedNutritionProvider")
            triggerEvaluation()
        }
    }

    public var selectedProfile: DietaryProfile {
        didSet {
            guard selectedProfile != oldValue else { return }
            triggerEvaluation()
        }
    }

    public var selectedProduct: FoodProduct {
        didSet {
            guard selectedProduct != oldValue else { return }
            triggerEvaluation()
        }
    }

    public var selectedPhotoItem: PhotosPickerItem? {
        didSet {
            loadSelectedPhoto()
        }
    }

    // Direct result properties
    public private(set) var decision: DietarySafetyDecision?
    public private(set) var isSafeProbability: Double?
    public private(set) var confidence: Double?
    public private(set) var latencyMs: Double = 0
    public private(set) var tokenUsage: (input: Int, output: Int) = (0, 0)
    public private(set) var usedVisionAttachment: Bool = false
    public private(set) var lastCapturedImage: CGImage?
    public private(set) var isEvaluating: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var scanStatus: String = "Waiting for Scan"

    public var onScanCompleted: (() -> Void)?

    private let modelOverride: (any LanguageModel)?
    @ObservationIgnored private var evaluationTask: Task<Void, Never>?
    @ObservationIgnored private var barcodeLookupTask: Task<Void, Never>?

    public let cameraService = CameraScannerService()
    public let openFoodFacts = OpenFoodFactsClient()

    public init(
        initialProfile: DietaryProfile = .celiacGlutenFree,
        initialProvider: NutritionScannerProvider = NutritionScannerProvider.autoDetectedDefault,
        model: (any LanguageModel)? = nil
    ) {
        self.selectedProfile = initialProfile
        self.selectedProvider = initialProvider
        self.selectedProduct = FoodProduct.emptyWaitingForScan
        self.modelOverride = model

        setupCameraCallbacks()
    }

    private func setupCameraCallbacks() {
        cameraService.onBarcodeDetected = { [weak self] barcode in
            self?.handleScannedBarcode(barcode)
        }

        cameraService.onLabelTextDetected = { [weak self] text, cgImage in
            self?.handleScannedOCRText(text, capturedImage: cgImage)
        }

        cameraService.onPhotoImportedWithoutOCR = { [weak self] cgImage in
            self?.handleImportedPhotoWithoutOCR(cgImage)
        }
    }

    public func handleScannedBarcode(_ barcode: String) {
        evaluationTask?.cancel()
        evaluationTask = nil
        barcodeLookupTask?.cancel()

        scanStatus = "Barcode: \(barcode)"
        errorMessage = nil
        isEvaluating = true
        lastCapturedImage = nil

        barcodeLookupTask = Task {
            let fetched = await openFoodFacts.fetchProduct(barcode: barcode)
            guard !Task.isCancelled else { return }

            guard self.cameraService.recognizedBarcode == barcode else { return }

            if let realProduct = fetched {
                self.selectedProduct = realProduct
                if realProduct.id.hasPrefix("unlisted-ingredients-") {
                    self.decision = nil
                    self.isSafeProbability = nil
                    self.confidence = nil
                    self.scanStatus = "\(realProduct.brand) found — scan label"
                    self.isEvaluating = false
                    self.onScanCompleted?()
                } else {
                    self.scanStatus = "Verified: \(realProduct.brand)"
                }
            } else {
                let unresolved = FoodProduct(
                    id: "unlisted-\(barcode)",
                    brand: "Unlisted Barcode",
                    name: "Barcode \(barcode)",
                    packageCategory: "Product",
                    barcode: barcode,
                    iconSystemName: "barcode.viewfinder",
                    ingredientsText: "Barcode \(barcode) was not found in Open Food Facts registry. Point the camera directly at the Ingredients or Nutrition Facts panel on the packaging to OCR and evaluate with \(selectedProvider.shortName).",
                    facilityWarning: nil,
                    nutrition: NutritionFacts(
                        servingSize: "––",
                        calories: 0,
                        totalFatGrams: 0,
                        saturatedFatGrams: 0,
                        sodiumMilligrams: 0,
                        totalCarbGrams: 0,
                        dietaryFiberGrams: 0,
                        totalSugarGrams: 0,
                        addedSugarGrams: 0,
                        proteinGrams: 0
                    )
                )
                self.decision = nil
                self.isSafeProbability = nil
                self.confidence = nil
                self.selectedProduct = unresolved
                self.scanStatus = "Barcode Found — Scan Label"
                self.isEvaluating = false
                self.onScanCompleted?()
            }
        }
    }

    public func handleScannedOCRText(_ rawText: String, capturedImage: CGImage? = nil) {
        let parsedNutrition = NutritionLabelParser.parseNutritionFacts(from: rawText)
        let (extractedIngredients, warning) = NutritionLabelParser.extractIngredientsAndAllergens(from: rawText)

        if isEvaluating || (
            selectedProduct.nutrition.calories == parsedNutrition.calories &&
            selectedProduct.nutrition.totalCarbGrams == parsedNutrition.totalCarbGrams &&
            selectedProduct.nutrition.proteinGrams == parsedNutrition.proteinGrams &&
            parsedNutrition.calories > 0
        ) {
            return
        }

        if let capturedImage {
            self.lastCapturedImage = capturedImage
        }

        scanStatus = "Nutrition Label Recognized"

        let ocrProduct = FoodProduct(
            id: "ocr-\(rawText.hashValue)",
            brand: "Scanned Label",
            name: "Nutrition Panel Scan",
            packageCategory: "Packaging OCR",
            barcode: selectedProduct.barcode != "––" ? selectedProduct.barcode : "Live OCR",
            iconSystemName: "text.viewfinder",
            ingredientsText: extractedIngredients,
            facilityWarning: warning,
            nutrition: parsedNutrition
        )

        self.selectedProduct = ocrProduct
    }

    private func handleImportedPhotoWithoutOCR(_ cgImage: CGImage) {
        self.lastCapturedImage = cgImage

        if selectedProvider.effectiveSupportsVision {
            scanStatus = "Photo Imported (Vision)"
            let visionProduct = FoodProduct(
                id: "photo-vision-\(UUID().uuidString.prefix(8))",
                brand: "Imported Photo",
                name: "Packaging Label Image",
                packageCategory: "Direct Vision Inspection",
                barcode: "Photo",
                iconSystemName: "photo.viewfinder",
                ingredientsText: "Inspect the attached packaging photograph directly to read ingredients, allergen advisories, and Nutrition Facts.",
                facilityWarning: nil,
                nutrition: NutritionFacts(
                    servingSize: "See Photo",
                    calories: 0,
                    totalFatGrams: 0,
                    saturatedFatGrams: 0,
                    sodiumMilligrams: 0,
                    totalCarbGrams: 0,
                    dietaryFiberGrams: 0,
                    totalSugarGrams: 0,
                    addedSugarGrams: 0,
                    proteinGrams: 0
                )
            )
            self.selectedProduct = visionProduct
        } else {
            self.decision = nil
            self.isEvaluating = false
            self.scanStatus = "No OCR Label Detected"
            self.errorMessage = "Could not detect a Nutrition Facts or Ingredients panel via OCR in the selected photo. Import a clearer label photo or switch to a multimodal vision provider (Cloudflare Clef, OpenAI Luna, or Google Gemini)."
            self.onScanCompleted?()
        }
    }

    private func loadSelectedPhoto() {
        guard let item = selectedPhotoItem else { return }
        self.onScanCompleted?()
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                scanStatus = "Photo Imported"
                errorMessage = nil
                cameraService.processStillImage(image)
            }
        }
    }

    public func toggleFlashlight() {
        cameraService.toggleTorch()
    }

    public func triggerEvaluation() {
        evaluationTask?.cancel()
        evaluationTask = nil

        let productToEval = selectedProduct
        let profileToEval = selectedProfile
        let providerToEval = selectedProvider

        guard productToEval.id != "waiting" && !productToEval.id.hasPrefix("unlisted-") else {
            isEvaluating = false
            return
        }

        isEvaluating = true
        errorMessage = nil
        decision = nil

        evaluationTask = Task { [weak self] in
            guard let self else { return }

            do {
                try Task.checkCancellation()
                let resolvedModel: any LanguageModel = try self.modelOverride ?? providerToEval.resolveConfiguredModel()

                let state = productToEval.formattedState(for: profileToEval)
                let visionSupported = providerToEval.effectiveSupportsVision
                let visualAttachmentImage: CGImage?
                if visionSupported {
                    if let existing = self.lastCapturedImage {
                        visualAttachmentImage = existing
                    } else {
                        visualAttachmentImage = await self.cameraService.snapshotCurrentFrame()
                    }
                } else {
                    visualAttachmentImage = nil
                }

                try Task.checkCancellation()

                let startTime = CFAbsoluteTimeGetCurrent()
                let response = try await Self.evaluateSafety(
                    using: resolvedModel,
                    state: state,
                    image: visualAttachmentImage
                )
                try Task.checkCancellation()
                let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

                if self.selectedProduct.id == productToEval.id &&
                   self.selectedProfile.id == profileToEval.id &&
                   self.selectedProvider == providerToEval {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        self.decision = response.content
                        self.isSafeProbability = response.probability(for: "isSafe") ?? (response.content.isSafe ? 1.0 : 0.0)
                        self.confidence = response.confidence(for: "primaryFlag")
                        self.latencyMs = duration
                        self.usedVisionAttachment = (visualAttachmentImage != nil)
                        self.tokenUsage = (
                            input: response.usage.input.totalTokenCount,
                            output: response.usage.output.totalTokenCount
                        )
                        self.errorMessage = nil
                        self.isEvaluating = false
                        self.onScanCompleted?()
                    }
                }
            } catch is CancellationError {
                return
            } catch let urlError as URLError where urlError.code == .cancelled {
                return
            } catch {
                guard !Task.isCancelled else { return }
                if self.selectedProduct.id == productToEval.id &&
                   self.selectedProfile.id == profileToEval.id &&
                   self.selectedProvider == providerToEval {
                    self.decision = nil
                    self.errorMessage = error.localizedDescription
                    self.scanStatus = "Evaluation Error"
                    self.isEvaluating = false
                    self.onScanCompleted?()
                }
            }
        }
    }

    private static func evaluateSafety(
        using model: some LanguageModel,
        state: String,
        image: CGImage?
    ) async throws -> LanguageModelSession.Response<DietarySafetyDecision> {
        let session = LanguageModelSession(model: model)
        if let image {
            let attachment = Attachment(image)
            let prompt = Prompt {
                state
                attachment
            }
            return try await session.respond(
                to: prompt,
                generating: DietarySafetyDecision.self
            )
        } else {
            return try await session.respond(
                to: state,
                generating: DietarySafetyDecision.self
            )
        }
    }
}
