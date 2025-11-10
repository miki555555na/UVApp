import SwiftUI

struct HeroView: View {
    let levels: GaugeLevels
    
    private var isDaytime: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 5 && hour < 18
    }
    
    var body: some View {
        ZStack {
            Spacer()
            if isDaytime {
                let energy =  levels.energy + 1
                // 元気度Aura
                Image("EnergyAura_\(energy)")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 460)
                    .opacity(0.8)
                // 昼：疲労度×日焼け度の16パターン
                Image("Base_Sun_L\(levels.sunburn)_Fat_P\(levels.fatigue)")
                    .resizable()
                    .scaledToFit()
                
                
            } else {
                // 夜：眠気クマ（眠気度に応じる）
                Image("SleepBear_\(levels.sleepiness)_Sun_L\(levels.sunburn)")
                    .resizable()
                    .scaledToFit()
            }
        }
    }
}


//
//ファイル名形式: Base_Sun_L[0-3]_Fat_P[0-3].png
//
//日焼け度 (Sunburn Color Tag):
//
//_Sun_L0: 健康な肌色（通常のキャラクターカラー）
//
//_Sun_L1: 少し赤みがかった肌色
//
//_Sun_L2: 真っ赤に火照った肌色
//
//_Sun_L3: 真っ黒に焼けた/炭化した肌色（ギャグ風）
//
//疲労度 (Fatigue Pose Tag):
//
//_Fat_P0: 元気に動き回るポーズ / 通常の立ち姿
//
//_Fat_P1: 少し疲れ気味、座っているポーズ
//
//_Fat_P2: ぐったり、汗だくのポーズ
//
//_Fat_P3: 倒れ込むポーズ / 半透明（体自体が透けている表現）
//
//作成すべき画像例 (計 4 (色)×4 (ポーズ)=16 種類):
//
//Base_Sun_L0_Fat_P0.png: 健康肌色で元気な立ち姿
//
//Base_Sun_L0_Fat_P1.png: 健康肌色で座っている姿
//
//Base_Sun_L0_Fat_P2.png: 健康肌色でぐったり姿
//
//Base_Sun_L0_Fat_P3.png: 健康肌色で倒れ込む姿
//
//Base_Sun_L1_Fat_P0.png: 少し赤い肌色で元気な立ち姿
//
//Base_Sun_L1_Fat_P1.png: 少し赤い肌色で座っている姿
//
//Base_Sun_L1_Fat_P2.png: 少し赤い肌色でぐったり姿
//
//Base_Sun_L1_Fat_P3.png: 少し赤い肌色で倒れ込む姿
//
//Base_Sun_L2_Fat_P0.png: 真っ赤な肌色で元気な立ち姿
//
//Base_Sun_L2_Fat_P1.png: 真っ赤な肌色で座っている姿
//
//Base_Sun_L2_Fat_P2.png: 真っ赤な肌色でぐったり姿
//
//Base_Sun_L2_Fat_P3.png: 真っ赤な肌色で倒れ込む姿
//
//Base_Sun_L3_Fat_P0.png: 真っ黒肌色で元気な立ち姿
//
//Base_Sun_L3_Fat_P1.png: 真っ黒肌色で座っている姿
//
//Base_Sun_L3_Fat_P2.png: 真っ黒肌色でぐったり姿
//
//Base_Sun_L3_Fat_P3.png: 真っ黒肌色で倒れ込む姿
//
//2. 修飾レイヤー画像（表情・一部ポーズ変更）
//HeroViewでは Image("Modifier\(modifierTag)") で呼び出されます。
//日中（元気度）と夜間（眠気度）で切り替わる、表情や一部ポーズを変更する画像です。
//
//ファイル名形式: Modifier_Gen_E[0-3].png または Modifier_Sleep_S[0-3].png または Modifier_Pose_[FORCED/LAZY].png
//
//元気度 (Genki Modifier Tag) - 日中用 (計 4 種類):
//
//_Gen_E3: キラキラした目と笑顔
//
//_Gen_E2: 標準の目と口
//
//_Gen_E1: 少し元気がない目と口（半分しゃがんだポーズに合わせて調整）
//
//_Gen_E0: うつむいた目と口（縮こまるポーズに合わせて調整）
//
//眠気度 (Sleepiness Modifier Tag) - 夜間用 (計 4 種類):
//
//_Sleep_S0: 覚醒している表情（日中の元気度に対応するような表情）
//
//_Sleep_S1: 少し眠そうな目と口（目が半開き）
//
//_Sleep_S2: 眠気MAX寸前の表情（目の下にクマや青い影、少し開いた口）
//
//_Sleep_S3: 完全にダウンしている表情（目を閉じ、口元が力ない）
//
//矛盾ポーズ (Pose Modifier Tag) - 特殊ケース (計 2 種類):
//
//_Pose_FORCED: 無理しているポーズと表情 (顔色悪いけど笑顔、疲労L2/L3のベースに笑顔とキラキラを無理やり適用したような表情)
//
//_Pose_LAZY: 怠惰なポーズと表情 (疲労L0/L1のベースに、うつむいて縮こまるような表情)
//
//作成すべき画像例 (計 4 (元気)+4 (眠気)+2 (矛盾)=10 種類):
//
//Modifier_Gen_E3.png: キラキラ笑顔
//
//Modifier_Gen_E2.png: 標準顔
//
//Modifier_Gen_E1.png: 元気ない顔（少し俯き加減）
//
//Modifier_Gen_E0.png: うつむく顔（完全に力なく俯く）
//
//Modifier_Sleep_S0.png: 覚醒顔（夜間でも眠くない元気な表情）
//
//Modifier_Sleep_S1.png: 少し眠そうな顔
//
//Modifier_Sleep_S2.png: Zzz顔（目の下のクマ、半開きの目）
//
//Modifier_Sleep_S3.png: ダウン顔（目を閉じ、力なく口が開いている）
//
//Modifier_Pose_FORCED.png: 無理笑顔（疲れたポーズだが、無理やり笑顔を作っている表情）
//
//Modifier_Pose_LAZY.png: 怠惰なポーズ（元気なはずだが、ダラけているようなポーズと表情）
//
//3. 個別エフェクト画像（最上層）
//HeroViewでは条件付きで Image("Effect_...") で呼び出されます。
//必要に応じて表示される、キャラクターを装飾するエフェクトです。
//
//ファイル名形式: Effect_Sparkle.png / Effect_Sweat.png / Effect_Zzz.png
//
//作成すべき画像例 (計 3 種類):
//
//Effect_Sparkle.png: 光のオーラ/キラキラのエフェクト
//
//キャラクターの周囲に舞うような、または体から発光するような効果
//
//Effect_Sweat.png: 汗マーク
//
//おでこや体の周りに複数配置されるような汗のしずくマーク
//
//Effect_Zzz.png: Zzzマーク
//
//キャラクターの頭上に出る、寝ていることを示すZzzマーク
