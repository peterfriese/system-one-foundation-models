import SwiftUI
import Foundation
import PhotosUI
import Observation
import FoundationModels
import JevFoundationModels

// MARK: - Main Actor Scanner View Model (Camera + Vision + Jev Foundation Models)

@MainActor
@Observable
public final class ScannerViewModel {
    public var selectedProfile: DietaryProfile {
        didSet {
            triggerEvaluation()
        }
    }

    public var selectedProduct: FoodProduct {
        didSet {
            triggerEvaluation()
        }
    }

    public var selectedPhotoItem: PhotosPickerItem? {
        didSet {
            loadSelectedPhoto()
        }
    }

    // Direct result properties (matching CLI demo ergonomics without intermediate wrapper)
    public private(set) var decision: DietarySafetyDecision?
    public private(set) var isSafeProbability: Double?
    public private(set) var confidence: Double?
    public private(set) var latencyMs: Double = 0
    public private(set) var tokenUsage: (input: Int, output: Int) = (0, 0)
    public private(set) var isEvaluating: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var scanStatus: String = "Waiting for Scan"

    public var onScanCompleted: (() -> Void)?

    public let model: JevLanguageModel
    public let cameraService = CameraScannerService()
    public let openFoodFacts = OpenFoodFactsClient()

    public init(
        initialProfile: DietaryProfile = .celiacGlutenFree,
        model: JevLanguageModel = .default
    ) {
        self.selectedProfile = initialProfile
        self.selectedProduct = FoodProduct.emptyWaitingForScan
        self.model = model

        setupCameraCallbacks()
    }

    private func setupCameraCallbacks() {
        cameraService.onBarcodeDetected = { [weak self] barcode in
            self?.handleScannedBarcode(barcode)
        }

        cameraService.onLabelTextDetected = { [weak self] text in
            self?.handleScannedOCRText(text)
        }
    }

    public func handleScannedBarcode(_ barcode: String) {
        scanStatus = "Barcode: \(barcode)"
        isEvaluating = true

        Task {
            let fetched = await openFoodFacts.fetchProduct(barcode: barcode)

            // Race guard: ignore stale network lookup if a newer barcode was scanned in the meantime
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
                    ingredientsText: "Barcode \(barcode) was not found in Open Food Facts registry. Please point the camera directly at the Ingredients or Nutrition Facts panel on the packaging to OCR and evaluate with Jev.",
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

    public func handleScannedOCRText(_ rawText: String) {
        let parsedNutrition = NutritionLabelParser.parseNutritionFacts(from: rawText)
        let (extractedIngredients, warning) = NutritionLabelParser.extractIngredientsAndAllergens(from: rawText)

        // Deduplicate OCR fluctuations on the same locked label
        if isEvaluating || (
            selectedProduct.nutrition.calories == parsedNutrition.calories &&
            selectedProduct.nutrition.totalCarbGrams == parsedNutrition.totalCarbGrams &&
            selectedProduct.nutrition.proteinGrams == parsedNutrition.proteinGrams &&
            parsedNutrition.calories > 0
        ) {
            return
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

    private func loadSelectedPhoto() {
        guard let item = selectedPhotoItem else { return }
        self.onScanCompleted?()
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                scanStatus = "Photo Imported"
                cameraService.processStillImage(image)
            }
        }
    }

    public func toggleFlashlight() {
        cameraService.toggleTorch()
    }

    public func triggerEvaluation() {
        let productToEval = selectedProduct
        let profileToEval = selectedProfile

        // Don't evaluate empty waiting placeholder or unresolved barcode prompts
        guard productToEval.id != "waiting" && !productToEval.id.hasPrefix("unlisted-") else { return }

        isEvaluating = true
        errorMessage = nil

        Task {
            do {
                // Direct Apple Foundation Models Session (matching CLI demo pattern)
                let session = LanguageModelSession(model: self.model)
                let state = productToEval.formattedState(for: profileToEval)

                let startTime = CFAbsoluteTimeGetCurrent()
                let response = try await session.respond(
                    to: state,
                    generating: DietarySafetyDecision.self
                )
                let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

                if self.selectedProduct.id == productToEval.id && self.selectedProfile.id == profileToEval.id {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        self.decision = response.content
                        self.isSafeProbability = response.probability(for: "isSafe") ?? (response.content.isSafe ? 1.0 : 0.0)
                        self.confidence = response.confidence(for: "primaryFlag")
                        self.latencyMs = duration
                        self.tokenUsage = (
                            input: response.usage.input.totalTokenCount,
                            output: response.usage.output.totalTokenCount
                        )
                        self.isEvaluating = false
                        self.onScanCompleted?()
                    }
                }
            } catch {
                if self.selectedProduct.id == productToEval.id && self.selectedProfile.id == profileToEval.id {
                    self.errorMessage = error.localizedDescription
                    self.scanStatus = "Evaluation Error: \(error.localizedDescription)"
                    self.isEvaluating = false
                    self.onScanCompleted?()
                }
            }
        }
    }
}
