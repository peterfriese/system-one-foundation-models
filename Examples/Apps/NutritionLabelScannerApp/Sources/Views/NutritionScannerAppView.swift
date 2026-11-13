import SwiftUI

// MARK: - Root Coordinator View (Camera Viewfinder + Interactive Sheet + Provider Settings)

public struct NutritionScannerAppView: View {
    @State private var viewModel = ScannerViewModel()
    @State private var isSheetPresented: Bool = false
    @State private var isProviderSettingsPresented: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            // (a) Full-Bleed Camera Viewfinder + Provider & Diet Selectors
            CameraViewfinderView(
                viewModel: viewModel,
                isSheetPresented: $isSheetPresented,
                isProviderSettingsPresented: $isProviderSettingsPresented
            )
        }
        .sheet(isPresented: $isSheetPresented) {
            // (d) Safety Indicators + (b) Nutrition Values
            NutritionSheetView(
                viewModel: viewModel,
                isSheetPresented: $isSheetPresented,
                onOpenProviderSettings: {
                    isSheetPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isProviderSettingsPresented = true
                    }
                }
            )
            .presentationDetents([.fraction(0.58), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isProviderSettingsPresented) {
            ProviderSettingsSheetView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.onScanCompleted = {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    if !isProviderSettingsPresented {
                        isSheetPresented = true
                    }
                }
            }
        }
    }
}
