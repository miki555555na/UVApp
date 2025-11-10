//
//  UVData.swift
//  UVHeroApp
//
//  Created by 永井美輝 on 2025/09/24.
//

import Foundation

//UVセンサーから取得したUVデータ（タイムスタンプ付き）を保持する構造体。
struct UVData: Identifiable, Codable {
    var id = UUID()              // SwiftUIリスト用に一意なID
    let timestamp: Date          // データ取得時刻
    let uvIndexOut: Double       // 外側UV
    let uvIndexIn: Double        // 内側UV
}

