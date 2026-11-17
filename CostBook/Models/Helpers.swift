import Foundation

extension Double {
    /// ¥1,234.5 —— 整数不带小数，有零头保留两位
    var moneyText: String {
        let v = abs(self)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = v == v.rounded() ? 0 : 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "0"
    }
}

extension Date {
    var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: self)
    }

    var dayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }

    /// 今天 / 昨天 / 11月17日 周二
    var dayLabel: String {
        let cal = Calendar.current
        let base = DateFormatter()
        base.locale = Locale(identifier: "zh_CN")
        base.dateFormat = "M月d日 EEE"
        let text = base.string(from: self)
        if cal.isDateInToday(self) { return "今天 · " + text }
        if cal.isDateInYesterday(self) { return "昨天 · " + text }
        return text
    }

    func addingMonths(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: n, to: self) ?? self
    }
}

// MARK: - CSV 导出
@MainActor
enum CSVExporter {
    static func make(from store: Store) -> String {
        var rows = [["日期", "类型", "分类", "金额", "备注"]]
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        for e in store.entries.sorted(by: { $0.date < $1.date }) {
            rows.append([
                f.string(from: e.date),
                e.type.title,
                store.category(e.categoryID)?.name ?? "未知",
                String(format: "%.2f", e.amount),
                e.note
            ])
        }
        return rows.map { r in
            r.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",")
        }.joined(separator: "\r\n")
    }

    /// 写入临时文件返回 URL，供 ShareLink 使用
    static func write(from store: Store) -> URL? {
        let csv = "\u{FEFF}" + make(from: store)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CostBook-\(Date().dayKey).csv")
        do {
            try csv.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }
}
