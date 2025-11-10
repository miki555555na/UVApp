import SwiftUI

struct SettingView: View {
    @ObservedObject var uvManager: UVForecastManager

    var body: some View {
        Form {
            Section(header: Text("都市選択")) {
                Picker("都市", selection: $uvManager.selectedCity) {
                    ForEach(Array(uvManager.cityCoordinates.keys), id: \.self) { city in
                        Text(city)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .onChange(of: uvManager.selectedCity) { _ in
            uvManager.fetchUVData() // 都市変更時に即時取得
        }
    }
}
