import UIKit
import BackgroundTasks


class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        
        // BGTask の登録
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.miki.UVApp.fetchUV",
            using: nil
        ) { task in
            self.handleUVFetchTask(task: task as! BGAppRefreshTask)
        }
        
        // 初回スケジュール
        scheduleUVFetch()
        
        return true
    }
    
    // 🔹 UV API を取るタスク処理
    private func handleUVFetchTask(task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        Task {
            await self.fetchAndSaveUVData()
            task.setTaskCompleted(success: true)
        }
        
        // 次回も忘れずにスケジュール
        scheduleUVFetch()
    }
    
    // 🔹 UV API を直接叩いて保存
    private func fetchAndSaveUVData() async {
        let cityCoordinates: [String:(lat: Double, lon: Double)] = [
            "東京": (35.6895, 139.6917),
            "大阪": (34.6937, 135.5023),
            "名古屋": (35.1815, 136.9066),
            "札幌": (43.0618, 141.3545),
            "福岡": (33.5902, 130.4017),
            "仙台": (38.2682, 140.8694),
            "広島": (34.3853, 132.4553),
            "神戸": (34.6901, 135.1955)
        ]

        var newFixedData: [String: FixedUVData] = [:]

        for (city, coord) in cityCoordinates {
            guard let url = URL(string: "https://api.openuv.io/api/v1/uv?lat=\(coord.lat)&lng=\(coord.lon)") else { continue }
            var request = URLRequest(url: url)
            request.addValue("openuv-jdovlrmfzkkukd-io", forHTTPHeaderField: "x-access-token")

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let result = try JSONDecoder().decode(CurrentUVResponse.self, from: data)
                
                // 都市ごとの固定UVを作成
                let fixedData = FixedUVData(
                    uvMax: result.result.uv_max,
                    fixedAt: Date()
                )
                newFixedData[city] = fixedData
                
                print("BGTask: \(city) UV max saved = \(result.result.uv_max)")

            } catch {
                print("UV fetch failed for \(city): \(error)")
            }
        }

        // まとめてUserDefaultsに保存
        if let encoded = try? JSONEncoder().encode(newFixedData) {
            UserDefaults.standard.set(encoded, forKey: "fixedTodayMaxUV")
        }
    }

    
    // 🔹 9時を目安にスケジュール
    private func scheduleUVFetch() {
        let request = BGAppRefreshTaskRequest(identifier: "com.miki.UVApp.fetchUV")
        
        var next9AM = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        if next9AM < Date() {
            next9AM = Calendar.current.date(byAdding: .day, value: 1, to: next9AM)!
        }
        request.earliestBeginDate = next9AM
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("BGTask scheduled for \(next9AM)")
        } catch {
            print("Failed to schedule BGTask: \(error)")
        }
    }
}

