import Foundation
import Combine
import SwiftUI

// JSTタイムゾーン
private let jst = TimeZone(identifier: "Asia/Tokyo")!

struct UVForecastData: Codable {
    let currentUV: Double
    let todayMaxUV: Double
}

struct CurrentUVResponse: Codable {
    let result: CurrentUVData
}
struct CurrentUVData: Codable {
    let uv: Double
    let uv_max: Double
}

private struct APIErrorResponse: Codable {
    let error: APIError
}
private struct APIError: Codable {
    let message: String
}

struct FixedUVData: Codable {
    let uvMax: Double
    let fixedAt: Date
}

final class UVForecastManager: ObservableObject {
    @Published var uvData: UVForecastData?                // 選択都市の現在値 + 今日の最大（表示用）
    @Published var selectedCity: String = "東京" {         // 選択都市（変更時に即 fetch）
        didSet {
            // 都市が変わったら画面をすぐ更新（時間外なら取得は行わない）
            fetchUVData()
        }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var todayMaxUVFixedTime: Date? = nil       // 表示用（選択都市の固定時刻）

    // UserDefaults と同期する fixedTodayMaxUV（全都市分）
    private(set) var fixedTodayMaxUV: [String: FixedUVData] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "fixedTodayMaxUV"),
                  let decoded = try? JSONDecoder().decode([String: FixedUVData].self, from: data) else {
                return [:]
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(encoded, forKey: "fixedTodayMaxUV")
            } else {
                UserDefaults.standard.removeObject(forKey: "fixedTodayMaxUV")
            }
        }
    }

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // 利用可能な都市座標（表示順を保ちたいなら Array にする）
    let cityCoordinates: [String:(lat: Double, lon: Double)] = [
        "東京": (lat: 35.6895, lon: 139.6917),
        "大阪": (lat: 34.6937, lon: 135.5023),
        "名古屋": (lat: 35.1815, lon: 136.9066),
        "札幌": (lat: 43.0618, lon: 141.3545),
        "福岡": (lat: 33.5902, lon: 130.4017),
        "仙台": (lat: 38.2682, lon: 140.8694),
        "広島": (lat: 34.3853, lon: 132.4553),
        "神戸": (lat: 34.6901, lon: 135.1955)
    ]

    private let apiKey = "自分のAPIにしてください"
    private let jstCalendar: Calendar = {
        var c = Calendar.current
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()

    init() {
        // アプリ起動時に（既定で）30分タイマーを開始
        startFetchingData()
        // 今日の fixed が存在しないなら BGTask がまだであっても
        // （アプリが起動しているなら）9時に全都市固定を試みる補助処理を予約しておく
        scheduleLocalFixAtNineIfNeeded()
    }

    deinit {
        stopFetchingData()
    }

    // MARK: - Timer 周り

    func startFetchingData() {
        stopFetchingData()
        // 起動時は即取得（ただし時間外なら取得は行われない）
        fetchUVData()

        // 30分周期
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            self?.fetchUVData()
        }
    }

    func stopFetchingData() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 時間判定

    private func isWithinActiveHours() -> Bool {
        let now = Date()
        let hour = jstCalendar.component(.hour, from: now)
        // 5 <= hour < 18 を有効時間とする
        return (5..<18).contains(hour)
    }

    // MARK: - fetch (選択都市のデータ取得)

    /// 選択都市の API を取得して `uvData` を更新する。
    /// API 呼び出しは 5~18 時のみ。9 時以降は fixedTodayMaxUV を参照して todayMaxUV を表示する。
    func fetchUVData() {
        // まず、日付が変わっていれば fixed データをリセットしておく
        resetFixedIfNewDay()

        guard let coord = cityCoordinates[selectedCity] else {
            self.errorMessage = "都市が未対応です: \(selectedCity)"
            return
        }

        // 時間外は API を叩かず、既存の fixed 値（もしあれば）を使って表示だけ更新する
        guard isWithinActiveHours() else {
            if let fixed = fixedTodayMaxUV[selectedCity] {
                // 時間外でも fixed があればそれを表示（currentUV は 0.0 を入れておく or nil にする）
                self.uvData = UVForecastData(currentUV: 0.0, todayMaxUV: fixed.uvMax)
                self.todayMaxUVFixedTime = fixed.fixedAt
                print("⏸ API取得は時間外。固定値を表示: \(selectedCity) -> \(fixed.uvMax)")
            } else {
                // 固定値も無ければ uvData を nil にしておく（または last-known を残す設計でも可）
                self.uvData = nil
                self.todayMaxUVFixedTime = nil
                print("⏸ API取得は時間外。固定値なし: \(selectedCity)")
            }
            return
        }

        // 通常の API 呼び出し（5~18時）
        isLoading = true
        errorMessage = nil

        let urlStr = "https://api.openuv.io/api/v1/uv?lat=\(coord.lat)&lng=\(coord.lon)"
        guard let url = URL(string: urlStr) else {
            self.isLoading = false
            self.errorMessage = "無効なURLです。"
            return
        }

        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "x-access-token")

        URLSession.shared.dataTaskPublisher(for: req)
            .map(\.data)
            .tryMap { data -> Data in
                if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                    throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: apiError.error.message])
                }
                return data
            }
            .decode(type: CurrentUVResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case .failure(let err) = completion {
                    self?.errorMessage = "データ取得エラー: \(err.localizedDescription)"
                    print("データ取得エラー: \(err)")
                }
            } receiveValue: { [weak self] response in
                guard let self = self else { return }

                let currentDate = Date()
                let hour = self.jstCalendar.component(.hour, from: currentDate)

                // today の開始
                let today = self.jstCalendar.startOfDay(for: currentDate)
                var currentFixed = self.fixedTodayMaxUV // read

                // 9時以降の固定ロジック（BGTask が既に入れていればそれを優先して使う）
                if hour < 9 {
                    // 9時前は API のまま表示（固定はまだない）
                    self.uvData = UVForecastData(currentUV: response.result.uv, todayMaxUV: response.result.uv_max)
                    self.todayMaxUVFixedTime = nil

                } else {
                    // 9時以降
                    if let savedFixed = currentFixed[self.selectedCity] {
                        // BGTask 等で固定済みならそれを使う（優先）
                        self.uvData = UVForecastData(currentUV: response.result.uv, todayMaxUV: savedFixed.uvMax)
                        self.todayMaxUVFixedTime = savedFixed.fixedAt
                    } else {
                        // fixed が無ければ、今受け取った uv_max を利用してその日の固定値を作成（フォールバック）
                        let fixed = FixedUVData(uvMax: response.result.uv_max, fixedAt: currentDate)
                        currentFixed[self.selectedCity] = fixed
                        self.fixedTodayMaxUV = currentFixed // save
                        self.uvData = UVForecastData(currentUV: response.result.uv, todayMaxUV: fixed.uvMax)
                        self.todayMaxUVFixedTime = fixed.fixedAt
                        print("⚠️ フォールバックで固定値作成（BGTask未実行）: \(self.selectedCity) = \(fixed.uvMax)")
                    }
                }

                // デバッグログ
                print("--- データ更新 ---")
                print("都市: \(self.selectedCity)")
                print("時刻 (JST): \(hour)時")
                print("現在UV: \(response.result.uv)")
                print("APIの今日の最大UV (受信): \(response.result.uv_max)")
                if let f = self.fixedTodayMaxUV[self.selectedCity] {
                    print("今日の最大UV表示 (固定済): \(f.uvMax) at \(f.fixedAt)")
                } else {
                    print("今日の最大UV表示 (未固定)")
                }
                print("----------------")
            }
            .store(in: &cancellables)
    }

    // MARK: - 日付変更時のリセット

    private func resetFixedIfNewDay() {
        // 固定データの日付が今日でない都市は削除する
        let today = jstCalendar.startOfDay(for: Date())
        var cur = fixedTodayMaxUV
        var changed = false
        for (city, fixed) in cur {
            if !jstCalendar.isDate(fixed.fixedAt, inSameDayAs: today) {
                cur[city] = nil
                changed = true
            }
        }
        if changed {
            fixedTodayMaxUV = cur
            print("🔁 fixedTodayMaxUV を日付切替でリセットしました")
        }
    }

    // MARK: - 補助: アプリ起動中に 9 時に自前で全都市固定を試みる（BGTask がなければフォールバック）
    // ただし、精密運用では BGTask が優先なので AppDelegate の BGTask 実装を残してください。
    func scheduleLocalFixAtNineIfNeeded() {
        // 既に今日分が固定済みならスキップ
        let today = jstCalendar.startOfDay(for: Date())
        if let anyFixed = fixedTodayMaxUV.values.first, jstCalendar.isDate(anyFixed.fixedAt, inSameDayAs: today) {
            return
        }

        // 次の 9:00（JST）まで待って fetchAllCitiesForFix() を呼ぶ
        var next9 = jstCalendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        if next9 < Date() {
            next9 = jstCalendar.date(byAdding: .day, value: 1, to: next9)!
        }
        let delay = next9.timeIntervalSince(Date())
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.fetchAllCitiesForFix()
        }
    }

    /// 9時に全都市分の uv_max を取りに行き fixedTodayMaxUV にまとめて保存する（補助）
    func fetchAllCitiesForFix() {
        print("⏳ fetchAllCitiesForFix: 全都市の uv_max を取得（補助処理）")
        let group = DispatchGroup()
        var newFixed: [String: FixedUVData] = [:]

        for (city, coord) in cityCoordinates {
            group.enter()
            guard let url = URL(string: "https://api.openuv.io/api/v1/uv?lat=\(coord.lat)&lng=\(coord.lon)") else {
                group.leave(); continue
            }
            var req = URLRequest(url: url)
            req.setValue(apiKey, forHTTPHeaderField: "x-access-token")

            URLSession.shared.dataTask(with: req) { data, _, err in
                defer { group.leave() }
                if let data = data, let resp = try? JSONDecoder().decode(CurrentUVResponse.self, from: data) {
                    let fixed = FixedUVData(uvMax: resp.result.uv_max, fixedAt: Date())
                    newFixed[city] = fixed
                    print("fetchAllCitiesForFix: \(city) -> \(fixed.uvMax)")
                } else {
                    if let e = err { print("fetchAllCitiesForFix error for \(city): \(e)") }
                }
            }.resume()
        }

        group.notify(queue: .main) {
            if !newFixed.isEmpty {
                self.fixedTodayMaxUV = newFixed
                print("✅ fetchAllCitiesForFix 完了。fixedTodayMaxUV を保存しました。")
            } else {
                print("⚠️ fetchAllCitiesForFix: 取得できた都市がありませんでした")
            }
        }
    }
}

