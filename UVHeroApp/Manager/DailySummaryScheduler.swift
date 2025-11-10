import Foundation
import CoreData

final class DailySummaryScheduler: ObservableObject {
    // その日の防御カウント
    var preventCount: Int = 0

    private var timer: Timer?
    var context: NSManagedObjectContext
    private let jst = TimeZone(identifier: "Asia/Tokyo")!

    init(context: NSManagedObjectContext) {
        self.context = context
        timer?.invalidate()
        scheduleDailyTask()
    }

    // MARK: - 日次スケジュール
    func scheduleDailyTask() {
        var calendar = Calendar.current
        calendar.timeZone = jst

        let now = Date()
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = 18 //調整
        comps.minute = 0
        comps.second = 0

        guard let today18 = calendar.date(from: comps) else { return }

        // 18:00 を過ぎていれば翌日の 18:00 をスケジュール
        let fireDate: Date = (now >= today18) ? calendar.date(byAdding: .day, value: 1, to: today18)! : today18
        var interval = fireDate.timeIntervalSince(now)
        // 念のための安全策（負やゼロ間隔は直ちに発火→再帰ループの原因になる）
        if interval <= 0 {
            let next = calendar.date(byAdding: .day, value: 1, to: today18)!
            interval = next.timeIntervalSince(now)
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.runDailyTask()
            self?.checkAndGrantBadges()
            self?.scheduleDailyTask()
        }

        print("💡 日次タスクをスケジュール: \(Formatter.formattedDateJST(fireDate)) JST")
    }

    // MARK: - 手動実行（テスト/時間外実行用）
    func runDailyNowForTesting() {
        runDailyTask()
        checkAndGrantBadges()
    }

    // MARK: - 日次タスク実行
    private func runDailyTask() {
        print("--- 🕖 18時処理開始 ---")

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) else { return }

        context.perform {
            let fetchRequest: NSFetchRequest<UVRecord> = UVRecord.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", todayStart as NSDate, todayEnd as NSDate)

            do {
                let records = try self.context.fetch(fetchRequest)
                guard !records.isEmpty else {
                    print("⚠️ 当日データなし。サマリー作成スキップ。")
                    return
                }

                // ゲージ計算（別クラス）
                let levels = GaugeCalculator.calculateLevels(context: self.context, within: todayStart..<todayEnd)
                print("💡 計算結果: \(levels)")

                // DailySummary 作成
                let summary = DailySummary(context: self.context)
                summary.date = todayStart
                summary.fatigue = Int16(levels.fatigue)
                summary.sunburn = Int16(levels.sunburn)
                summary.energy = Int16(levels.energy)
                summary.sleepiness = Int16(levels.sleepiness)
                summary.preventCount = Int16(self.preventCount)
                // その日に10回以上防げていれば成功とみなす
                summary.preventSuccess = self.preventCount >= 10

                // 当日データ削除
                records.forEach { self.context.delete($0) }

                try self.context.save()
                print("✅ サマリー保存 & 当日データ削除完了")

                self.cleanupOldSummaries()
            } catch {
                print("❌ 日次処理エラー: \(error.localizedDescription)")
                self.context.rollback()
            }
        }
    }

    // MARK: - 古いサマリー削除
    private func cleanupOldSummaries() {
        context.perform {
            let fetchRequest: NSFetchRequest<DailySummary> = DailySummary.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

            do {
                let summaries = try self.context.fetch(fetchRequest)
                if summaries.count > 7 {
                    summaries.suffix(from: 7).forEach { self.context.delete($0) }
                    try self.context.save()
                    print("🗑️ 古いサマリー (\(summaries.count - 7)件) を削除")
                }
            } catch {
                print("❌ サマリー削除エラー: \(error.localizedDescription)")
                self.context.rollback()
            }
        }
    }

    // MARK: - バッジ判定
    func checkAndGrantBadges() {
        let fetchRequest: NSFetchRequest<DailySummary> = DailySummary.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        do {
            let summaries = try context.fetch(fetchRequest)
            var calendar = Calendar.current
            calendar.timeZone = jst

            // 連続成功日数を計算（今日から過去に向かって連続している日を数える）
            var consecutiveSuccessDays = 0
            var expectedDate: Date? = nil
            
            for summary in summaries {
                guard let summaryDate = summary.date else { continue }
                
                // 最初の日（最新の日）の場合
                if expectedDate == nil {
                    if summary.preventSuccess {
                        consecutiveSuccessDays = 1
                        expectedDate = calendar.date(byAdding: .day, value: -1, to: summaryDate)
                    } else {
                        break // 最新の日が失敗なら連続は0
                    }
                } else {
                    // 期待する日付と一致するかチェック
                    let summaryDay = calendar.startOfDay(for: summaryDate)
                    let expectedDay = calendar.startOfDay(for: expectedDate!)
                    
                    if summaryDay == expectedDay {
                        if summary.preventSuccess {
                            consecutiveSuccessDays += 1
                            expectedDate = calendar.date(byAdding: .day, value: -1, to: summaryDate)
                        } else {
                            break // 途切れた
                        }
                    } else if summaryDay < expectedDay {
                        // 日付が飛んでいる（途切れている）
                        break
                    }
                    // summaryDay > expectedDay の場合は古いデータなのでスキップ
                }
            }

            // 防御初心者：3日以上連続成功
            if consecutiveSuccessDays >= 3 {
                grantBadgeIfNeeded(name: "防御初心者")
            } else {
                removeBadgeIfExists(name: "防御初心者")
            }

            // 防御マスター：7日以上連続成功
            if consecutiveSuccessDays >= 7 {
                grantBadgeIfNeeded(name: "防御マスター")
            } else {
                removeBadgeIfExists(name: "防御マスター")
            }

            print("📊 連続成功日数: \(consecutiveSuccessDays)日")
        } catch {
            print("❌ 称号判定エラー: \(error.localizedDescription)")
        }
    }

    func removeBadgeIfExists(name: String) {
        let fetchRequest: NSFetchRequest<Badge> = Badge.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name == %@", name)
        do {
            let existing = try context.fetch(fetchRequest)
            if !existing.isEmpty {
                existing.forEach { context.delete($0) }
                try context.save()
                print("🗑️ バッジ \(name) を削除しました")
            }
        } catch {
            print("❌ バッジ削除エラー: \(error.localizedDescription)")
        }
    }


    func grantBadgeIfNeeded(name: String) {
        let fetchRequest: NSFetchRequest<Badge> = Badge.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name == %@", name)

        if let existing = try? context.fetch(fetchRequest), !existing.isEmpty {
            print("🎖️ バッジ \(name) は既に取得済み")
            return
        }

        let badge = Badge(context: context)
        badge.id = UUID()
        badge.name = name
        badge.dateEarned = Date()

        do {
            try context.save()
            print("🏅 バッジ「\(name)」を取得！")
        } catch {
            print("❌ バッジ保存エラー: \(error.localizedDescription)")
        }
    }

    // MARK: - 即時付与（テスト用）
    // 現在の防御回数が1回以上なら「防御初心者」を即時付与
    func grantBeginnerIfCurrentCountAtLeastOnce(currentCount: Int) {
        if currentCount >= 0 {
            grantBadgeIfNeeded(name: "防御初心者")
        }
    }

    // JST Formatter
    struct Formatter {
        static func formattedDateJST(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
            formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
            return formatter.string(from: date)
        }
    }
}


