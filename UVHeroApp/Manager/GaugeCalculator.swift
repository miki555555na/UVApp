//ゲージ計算

//疲労度ゲージ(4段階)
//日焼けゲージ(4段階)
//元気度ゲージ(4段階)
//眠気ゲージ(4段階)

import Foundation
import CoreData

struct GaugeLevels {
    let fatigue: Int
    let sunburn: Int
    let energy: Int
    let sleepiness: Int
}

/// リアルタイムゲージ計算（必要に応じて期間指定）
final class GaugeCalculator {
    /// 全レコードではなく、引数で与えた期間内のレコードを集計するようにした（テスト性向上）
    static func calculateLevels(context: NSManagedObjectContext, within range: Range<Date>? = nil) -> GaugeLevels {
        let fetchRequest: NSFetchRequest<UVRecord> = UVRecord.fetchRequest()

        if let r = range {
            fetchRequest.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", r.lowerBound as NSDate, r.upperBound as NSDate)
        }

        do {
            let records = try context.fetch(fetchRequest)

            // 調整後uvIn: 表示と同じ式でロジックも評価
            // adjustedUVIn = (uvIn + 1) * 2.5
            let adjustedIns = records.map { ($0.uvIn + 1.0) * 2.1 }

            // 疲労度：調整後uvIn >= 6 の回数
            
            let fatigueCount = adjustedIns.filter { $0 >= 6.0 }.count
            // 閾値はサンプル。必要に応じて調整してください
            let fatigueThresholds = [0,10,20,30]
            let fatigueLevel = fatigueThresholds.filter { fatigueCount > $0 }.count 

            // 日焼け度：調整後uvIn の合計
            let totalIn = adjustedIns.reduce(0.0, +)
            let sunburnThresholds = [0,300,600,1200]
            let sunburnLevel = sunburnThresholds.filter { totalIn > Double($0) }.count


            // 元気度：調整後uvIn が 2〜5 の回数
            let moderateCount = adjustedIns.filter { $0 >= 2 && $0 <= 5 }.count
            let genkiLevel: Int
            if moderateCount == 0 { genkiLevel = 0 }
            else if moderateCount < 5 { genkiLevel = 1 }
            else if moderateCount < 10 { genkiLevel = 2 }
            else if moderateCount < 15 { genkiLevel = 3 }
            else if moderateCount < 30 { genkiLevel = 3 }
            else if moderateCount < 50 { genkiLevel = 2 }
            else { genkiLevel = 1 }

            // 眠気度：疲労度と元気度の組み合わせ（サンプルロジック）
            var sleepinessLevel = 3
            if genkiLevel == 0 { sleepinessLevel = 3 }
            else if fatigueLevel < 3 && genkiLevel == 3 { sleepinessLevel = 0 }
            else if fatigueLevel < 10 && genkiLevel == 2 { sleepinessLevel = 1 }            else if fatigueLevel < 10 && genkiLevel == 2 { sleepinessLevel = 1 }
            else if fatigueLevel < 10 && genkiLevel == 1 { sleepinessLevel = 2 }


            return GaugeLevels(fatigue: fatigueLevel, sunburn: sunburnLevel, energy: genkiLevel, sleepiness: sleepinessLevel)
        } catch {
            print("❌ CoreData fetch error: \(error)")
            return GaugeLevels(fatigue: 0, sunburn: 0, energy: 0, sleepiness: 0)
        }
    }
}
