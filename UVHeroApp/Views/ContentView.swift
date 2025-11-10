import SwiftUI
import CoreData

// MARK: - 吹き出し用カスタムShape
struct SpeechBubble: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // 吹き出し本体
        let bubbleRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height * 0.85
        )
        path.addRoundedRect(in: bubbleRect, cornerSize: CGSize(width: 12, height: 12))
        
        // 吹き出しの三角（下側中央）
        let midX = rect.midX - 15
        let bottomY = rect.maxY
        let triangleHeight: CGFloat = rect.height * 0.15
        
        path.move(to: CGPoint(x: midX - 10, y: bubbleRect.maxY))
        path.addLine(to: CGPoint(x: midX + 10, y: bubbleRect.maxY))
        path.addLine(to: CGPoint(x: midX, y: bottomY))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - 吹き出しビュー
struct SpeechBubbleView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.body)
            .foregroundColor(.black)
            .padding(10)    
            .background(
                SpeechBubble()
                    .fill(Color.white.opacity(0.9))
            )
            .overlay(
                SpeechBubble()
                    .stroke(Color.gray, lineWidth: 1)
            )
            .frame(maxWidth: 200) // 吹き出しの幅制限
    }
}


// MARK: - ContentView
struct ContentView: View {
    @Environment(\.managedObjectContext) private var context
    @StateObject private var bleManager = BLEManager()
    @StateObject private var uvManager = UVForecastManager()
    @StateObject private var dailyScheduler: DailySummaryScheduler

    @State private var levels: GaugeLevels = GaugeLevels(fatigue: 0, sunburn: 0, energy: 0, sleepiness: 0)
    @State private var showingSettings = false
    @State private var preventCount = 0  // UI用カウント
    @State private var lastPreventionSuccess: Date? = nil  // 重複カウント防止
    @State private var heartAnimated: Bool = false  // ハート表示アニメ用
    @State private var heartPulse: Bool = false     // ハート鼓動アニメ用
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DailySummary.date, ascending: false)],
        animation: .default
    ) private var dailySummaries: FetchedResults<DailySummary>
    
    private var dailySummary: DailySummary? { dailySummaries.first }
    
    private var currentHour: Int {
        Calendar.current.component(.hour, from: Date())
    }
    
    private var isAfter18: Bool { currentHour >= 18 }
    private var isDisplayableTime: Bool { currentHour >= 5 && currentHour < 24 }
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Badge.dateEarned, ascending: false)],
        animation: .default
    ) private var badges: FetchedResults<Badge>


    init() {
        _dailyScheduler = StateObject(wrappedValue: DailySummaryScheduler(
            context: PersistenceController.shared.container.viewContext
        ))
    }

    private var displayLevels: GaugeLevels {
        if isAfter18, let summary = dailySummary {
            return GaugeLevels(
                fatigue: Int(summary.fatigue),
                sunburn: Int(summary.sunburn),
                energy: Int(summary.energy),
                sleepiness: Int(summary.sleepiness)
            )
        } else {
            return levels
        }
    }

    // 変換後のUV値（表示と同じ計算式をロジックでも使用）
    private var adjustedUVOut: Double { (bleManager.currentUVIndexOut + 1.2) * 2.5 }
    private var adjustedUVIn: Double { (bleManager.currentUVIndexIn + 1) * 2.1 }
    
    // ハート表示条件：生のUV値で比較し、外側UVが0より大きい場合のみ
    private var shouldShowHeart: Bool {
        bleManager.currentUVIndexOut > bleManager.currentUVIndexIn && 
        bleManager.currentUVIndexOut > 0.0 && 
        !isAfter18
    }

    private var comment: String {
        if !isAfter18 {
            if displayLevels.energy == 0 {
                return "少しお散歩に出かけよう！"
            } else if displayLevels.fatigue >= displayLevels.sunburn {
                return "一回室内で涼もう！水分補給も忘れないでね！"
            } else {
                return "日陰は周りにある？日陰を歩いてみよう！"
            }
        }
        return ""
    }

    private var praiseComment: String? {
        guard let summary = dailySummary else { return nil }
        let todayPrevent = Int(summary.preventCount)
        if isAfter18 && todayPrevent >= 2 {
            return "今日も紫外線をよく防げたね！えらい！"
        } else if isAfter18 && todayPrevent < 2 {
            return "明日は日傘や帽子を持ってお出かけしよう！"
        }
        return nil
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .topTrailing) {
                // Full-screen background
                Color(red: 0.9, green: 0.98, blue: 1.0)
                    .ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        ZStack(alignment: .topLeading) {
                            HeroView(levels: displayLevels)
                                .frame(width: 250, height: 250)
                                .padding(.top, 130)

                            // ハート表示（常時レイヤーに置いて、可視状態をアニメで切替）
                            Image(systemName: "heart.fill")
                                .foregroundColor(.pink)
                                .font(.system(size: 30))
                                .padding(.leading, 10)
                                .padding(.top, 18)
                                .zIndex(1)
                                .scaleEffect(heartPulse ? 1.08 : 0.92)
                                .opacity(heartAnimated ? 1.0 : 0.0)
                                // .animation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0.2), value: heartAnimated)
                                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: heartPulse)

                            // 王冠表示（左上・ハート付近に大きめに表示）
                            HStack(spacing: 8) {
                                if badges.contains(where: { $0.name == "防御初心者" }) {
                                    Image("crown_beginner")
                                        .resizable()                               
                                        .frame(width: 40, height: 40)
                                }
                                if badges.contains(where: { $0.name == "防御マスター" }) {
                                    Image("crown_master")
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                }
                            }
                            .padding(.leading, 15)
                            .offset(x: -8, y: -25)
                            .zIndex(1)

                            if !isAfter18 {
                                SpeechBubbleView(text: comment)
                                    .offset(x: 55, y: 110)
                                    .zIndex(1)
                            } else if let comment = praiseComment {
                                SpeechBubbleView(text: comment)
                                    .offset(x: 55, y: 110)
                                    .zIndex(1)
                            }
                        }
                        .onChange(of: bleManager.currentUVIndexOut) { _ in 
                            checkPrevention()
                            updateHeartDisplay()
                        }
                        .onChange(of: bleManager.currentUVIndexIn) { _ in 
                            checkPrevention()
                            updateHeartDisplay()
                        }

                        Spacer()

                        if isDisplayableTime {
                            if !isAfter18 {
                                APISummaryView(uvManager: uvManager)
                                    .padding(.top)
                                Divider().padding(.vertical)
                                BLEDataView(bleManager: bleManager)
                                    .padding(.bottom)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                VStack(alignment: .trailing, spacing: 6) {
                    GaugeBar(value: displayLevels.fatigue, maxValue: 3, color: .red, icon: "疲労度💦")
                    GaugeBar(value: displayLevels.sunburn, maxValue: 3, color:.orange, icon:"日焼け度☀️")
                    GaugeBar(value: displayLevels.energy, maxValue: 3, color:.green, icon:"元気度⚡️")
                    GaugeBar(value: displayLevels.sleepiness, maxValue: 3, color: .blue, icon:"眠気度😴")
                }
                .padding(10)
                .background(Color.black.opacity(0.6))
                .cornerRadius(12)
                .frame(width: UIScreen.main.bounds.width * 0.45, height: UIScreen.main.bounds.height / 2, alignment: .top)
                .padding([.top, .trailing], 12)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { // ナビゲーションバー中央に配置
                    HStack(spacing: 4) {
//                        Text("UVヒーロー")
//                            .font(.headline)
                        // 画面上部（ハート付近）に王冠を表示するため、ここでの表示は廃止
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }

            .sheet(isPresented: $showingSettings) {
                SettingView(uvManager: uvManager)
            }
            .onAppear {
                uvManager.startFetchingData()
                if !isAfter18 {
                    levels = GaugeCalculator.calculateLevels(context: context)
                }
                dailyScheduler.context = context
                dailyScheduler.scheduleDailyTask()
                // バッジ判定を実行（アプリ起動時にも最新の状態を反映）
                dailyScheduler.checkAndGrantBadges()
                // 初期のハート表示状態を反映
                updateHeartDisplay()
            }
            .onReceive(Timer.publish(every: 3600, on: .main, in: .common).autoconnect()) { _ in
                // 1時間ごとにゲージ再計算（18時前のみ）
                if !isAfter18 {
                    levels = GaugeCalculator.calculateLevels(context: context)
                }
            }
            .onDisappear {
                uvManager.stopFetchingData()
            }
        }
    }

    private func updateHeartDisplay() {
        let shouldShow = shouldShowHeart
        heartAnimated = shouldShow
        if shouldShow {
            heartPulse = false
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                heartPulse = true
            }
        } else {
            heartPulse = false
        }
    }
    
    private func checkPrevention() {
        // 前回から一定時間経過した場合のみカウント（例: 1分間隔）
        let now = Date()
        if adjustedUVOut > adjustedUVIn,
           lastPreventionSuccess == nil || now.timeIntervalSince(lastPreventionSuccess!) > 60 {
            preventCount += 1
            lastPreventionSuccess = now

            // DailySummary にも反映
            if let summary = dailySummary {
                summary.preventCount = Int16(preventCount)
                try? context.save()
            }

        }
    }
}


// MARK: - キャラ＋常時ゲージ表示
struct HeroWithGaugesView: View {
    var levels: GaugeLevels
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // キャラクター
            HeroView(levels: levels)
                .frame(width: 250, height: 250)
            
            // 右上ゲージ
            VStack(alignment: .trailing, spacing: 6) {
                GaugeBar(value: levels.fatigue, maxValue: 10, color: .red, icon: "💤")     // 疲労
                GaugeBar(value: levels.sunburn, maxValue: 10, color: .orange, icon: "☀️") // 日焼け
                GaugeBar(value: levels.energy, maxValue: 4, color: .green, icon: "⚡️")    // 元気

            }
            .padding(8)
            .background(Color.black.opacity(0.4)) // 半透明で背景まとめ
            .cornerRadius(8)
            .padding([.top, .trailing], 12)
        }
    }
}

// MARK: - ゲージUI（横長バー）
struct GaugeBar: View {
    let value: Int
    let maxValue: Int
    let color: Color
    let icon: String
    @State private var showValue: Bool = false
    
    var body: some View {
        HStack(spacing: 6) {
            Text(icon)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .onTapGesture {
                    showValue = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showValue = false
                    }
                }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: CGFloat(value) / CGFloat(maxValue) * geometry.size.width)
                }
            }
            .frame(height: 8)

            if showValue {
                Text("\(value)")
                    .font(.caption2)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(6)
            }
        }
        .frame(height: 12)
    }
}


// MARK: - API表示部分
struct APISummaryView: View {
    @ObservedObject var uvManager: UVForecastManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            Text("🌍 UV予報（観測地点：\(uvManager.selectedCity)）")
                .font(.system(.title2, design: .rounded).bold())
            
            if let uvData = uvManager.uvData {
                VStack(alignment: .leading, spacing: 8) {
                    Text("現在のUVインデックス：\(String(format: "%.2f", uvData.currentUV))")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("今日の最大UVインデックス：\(uvData.todayMaxUV, specifier: "%.1f")")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    
                    // if let time = uvManager.todayMaxUVFixedTime {
                    //     Text("固定時刻: \(time.formatted(date: .omitted, time: .shortened))")
                    // } else {
                    //     Text("固定時刻: まだ未固定")
                    //         .foregroundColor(.gray)
                    // }
                    
                    Text("更新時刻（JST）：\(formattedDateJST(Date()))")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            } else {
                Text("データ取得中...")
                    .foregroundColor(.gray)
            }
        }
    }
    
    private func formattedDateJST(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - BLE表示部分
struct BLEDataView: View {
    @ObservedObject var bleManager: BLEManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🛰️ UVセンサー（BLE）")
                .font(.system(.title2, design: .rounded).bold())
            
            VStack(alignment: .leading, spacing: 8) {
                Text("外側UV（直射光）：\(String(format: "%.2f", bleManager.currentUVIndexOut))")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("内側UV（防御後）：\(String(format: "%.2f", bleManager.currentUVIndexIn))")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(10)

            // UVインデックス凡例
            UVLegendView()
                .padding(.top, 16)
        }
    }
}

// MARK: - UVインデックス凡例
struct UVLegendView: View {
    private let chipSize = CGSize(width: 52, height: 22)
    private let spacing: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 見出し行
            HStack(alignment: .firstTextBaseline) {
                Text("UVインデックスの指標と対策")
                    .font(.caption)
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Text("それに応じた紫外線対策")
                //     .font(.caption)
                //     .bold()
                //     .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 本体（左:数値チップ 縦、右:説明 テキストを段間に）
            HStack(alignment: .top, spacing: 12) {
                // 左: 数字チップ（縦並び）
                VStack(alignment: .leading, spacing: spacing) {
                    UVLegendChip(color: Color(#colorLiteral(red: 0.890, green: 0.000, blue: 0.780, alpha: 1.0)), text: "11+")
                    UVLegendChip(color: .red, text: "8〜10")
                    UVLegendChip(color: .orange, text: "6〜7")
                    UVLegendChip(color: .yellow, text: "3〜5")
                    UVLegendChip(color: Color(red: 0.65, green: 0.80, blue: 1.0), text: "1〜2")
                }

                // 右: 説明（縦並びの“間”に配置）
                GeometryReader { _ in
                    let row = chipSize.height + spacing
                    let totalHeight = row * 4 + chipSize.height
                    ZStack(alignment: .topLeading) {
                        // 11+（チップの高さ中央に合わせる）
                        Text("極端に強い。日中の外出は避けよう。")
                            .font(.caption)
                            .foregroundColor(.primary)
                            .offset(y: chipSize.height/2 - 6)

                        // 8〜10 と 6〜7 の“間”
                        Text("強い〜非常に強い。日陰・日傘・帽子は必須。")
                            .font(.caption)
                            .foregroundColor(.primary)
                            .offset(y: row + chipSize.height + spacing/2 - 6)

                        // 3〜5 と 1〜2 の“間”
                        Text("弱い〜中程度。日傘や帽子があると安心。")
                            .font(.caption)
                            .foregroundColor(.primary)
                            .offset(y: row*3 + chipSize.height + spacing/2 - 6)
                    }
                    .frame(height: totalHeight, alignment: .topLeading)
                }
                .frame(width: 240)
            }
        }
    }
}


struct UVLegendChip: View {
    let color: Color
    let text: String

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color)
            .frame(width: 52, height: 22)
            .overlay(
                Text(text)
                    .font(.caption2)
                    .bold()
                    .foregroundColor(.black)
            )
    }
}

// MARK: - ゲージ表示部分
struct GaugeView: View {
    @Binding var levels: GaugeLevels
    var context: NSManagedObjectContext
    var dailySummary: DailySummary? // 18時以降はここから値を取得
    private let jst = TimeZone(identifier: "Asia/Tokyo")!
    
    private var isAfter18: Bool {
        let now = Date()
        let calendar = Calendar.current
        var comps = calendar.dateComponents(in: jst, from: now)
        let hour = comps.hour ?? 0
        return hour >= 18
        
    }
    
    // 表示用レベル
    private var displayLevels: GaugeLevels {
        if isAfter18, let summary = dailySummary {
            return GaugeLevels(
                fatigue: Int(summary.fatigue),
                sunburn: Int(summary.sunburn),
                energy: Int(summary.energy),
                sleepiness: Int(summary.sleepiness)
            )
        } else {
            return levels
        }
    }

    
    var body: some View {
        VStack(spacing: 8) {
            Text("ゲージ表示")
                .font(.title)
            
            Text("疲労度: \(displayLevels.fatigue)")
            Text("日焼け度: \(displayLevels.sunburn)")
            Text("元気度: \(displayLevels.energy)")
            Text("眠気度: \(displayLevels.sleepiness)")
            
            if !isAfter18 {
                Button("再計算") {
                    levels = GaugeCalculator.calculateLevels(context: context)
                }
                .padding()
                .background(Color.blue.opacity(0.2))
                .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

