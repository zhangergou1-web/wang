import Foundation

// MARK: - 解析出的单行（分类还是名字，尚未落库）
struct ParsedRow {
    var type: EntryType
    var amount: Double
    var categoryName: String
    var note: String
    var date: Date

    var signature: String {
        "\(Int(date.timeIntervalSince1970 / 60))|\(type.rawValue)|\(amount)|\(categoryName)|\(note)"
    }
}

// MARK: - 导入结果
struct ImportResult {
    var added: Int = 0
    var skipped: Int = 0
    var duplicates: Int = 0
    var errors: [String] = []
    var previewRows: [ParsedRow] = []
    var totalParsed: Int = 0

    var summary: String {
        var parts: [String] = []
        if added > 0 { parts.append("导入 \(added) 条") }
        if duplicates > 0 { parts.append("跳过重复 \(duplicates) 条") }
        if skipped > 0 { parts.append("无法识别 \(skipped) 条") }
        if parts.isEmpty { parts.append("没有可导入的数据") }
        return parts.joined(separator: "，")
    }
}

// MARK: - CSV 解析
enum CSV {
    /// 支持逗号/制表符/分号分隔，支持引号包裹、引号内换行与逗号
    static func rows(from text: String, separator: Character? = nil) -> [[String]] {
        var input = text
        if input.hasPrefix("\u{FEFF}") { input.removeFirst() }

        let sep: Character = separator ?? detectSeparator(input)
        var result: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var i = input.startIndex

        while i < input.endIndex {
            let c = input[i]
            if inQuotes {
                if c == "\"" {
                    let next = input.index(after: i)
                    if next < input.endIndex && input[next] == "\"" {
                        field.append("\"")
                        i = input.index(after: next)
                        continue
                    }
                    inQuotes = false
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == sep {
                row.append(field)
                field = ""
            } else if c == "\n" {
                row.append(field)
                result.append(row)
                row = []
                field = ""
            } else if c != "\r" {
                field.append(c)
            }
            i = input.index(after: i)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            result.append(row)
        }
        return result.filter { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    private static func detectSeparator(_ text: String) -> Character {
        let head = text.prefix(2000)
        let options: [(Character, Int)] = [
            (",", head.filter { $0 == "," }.count),
            ("\t", head.filter { $0 == "\t" }.count),
            (";", head.filter { $0 == ";" }.count)
        ]
        return (options.max { $0.1 < $1.1 }?.0) ?? ","
    }
}

// MARK: - 字段识别
enum FieldKind {
    case date, amount, category, note, type
}

/// 各家记账软件常见的列名
private let columnHints: [FieldKind: [String]] = [
    .date: ["日期", "时间", "交易时间", "记账日期", "date", "time", "transactiondate", "created"],
    .amount: ["金额", "money", "amount", "value", "收支金额", "金额(元)", "数值"],
    .category: ["分类", "类别", "category", "类目", "账单分类", "消费类型"],
    .note: ["备注", "说明", "note", "memo", "description", "摘要", "商家", "备注信息", "商品说明", "交易对象"],
    .type: ["类型", "收支", "收支类型", "type", "收/支", "交易类型", "方向", "收支方向"]
]

/// 分类关键词表：把任意软件的分类名归并到本 App 的分类
private let categoryAliases: [String: [String]] = [
    "餐饮": ["餐饮", "吃饭", "food", "restaurant", "外卖", "美食", "餐厅", "咖啡", "奶茶", "早餐", "午餐", "晚餐", "零食", "夜宵"],
    "交通": ["交通", "出行", "transport", "taxi", "打车", "地铁", "公交", "加油", "停车", "机票", "火车", "滴滴"],
    "购物": ["购物", "shopping", "服饰", "衣服", "数码", "电子", "美妆", "鞋", "包"],
    "日用": ["日用", "生活", "超市", "groceries", "家居", "日用百货", "日常", "洗护", "纸"],
    "房租": ["房租", "租房", "rent", "住房", "房贷", "物业"],
    "水电": ["水电", "电费", "水费", "燃气", "utility", "取暖", "煤气"],
    "通讯": ["通讯", "话费", "流量", "网费", "宽带", "电话费"],
    "娱乐": ["娱乐", "游戏", "电影", "休闲", "entertainment", "音乐", "会员", "运动", "健身"],
    "医疗": ["医疗", "医药", "看病", "health", "药", "体检", "门诊", "挂号"],
    "学习": ["学习", "教育", "书", "education", "培训", "课程", "文具", "学费"],
    "人情": ["人情", "礼品", "gift", "请客", "礼金", "社交", "送礼"],
    "旅行": ["旅行", "旅游", "travel", "酒店", "门票", "住宿"],
    "工资": ["工资", "薪水", "salary", "薪资", "打工", "劳务"],
    "奖金": ["奖金", "bonus", "绩效", "提成", "奖励"],
    "兼职": ["兼职", "副业", "parttime", "外快", "稿费"],
    "理财": ["理财", "投资", "收益", "利息", "基金", "股票", "分红", "利息收入"],
    "红包": ["红包", "压岁钱", "转入"],
    "报销": ["报销", "reimburse", "退款", "返现"],
    "其他": ["其他", "其它", "other", "未知", "杂项", "未分类"]
]

// MARK: - 导入器
enum Importer {
    static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{3000}", with: "")
            .lowercased()
    }

    static func fallbackIcon(_ name: String) -> String {
        CategoryIcon.guess(name)
    }

    /// 表头 → 列下标
    static func mapColumns(_ header: [String]) -> [FieldKind: Int] {
        var map: [FieldKind: Int] = [:]
        let lowered = header.map { normalize($0) }

        // 先做精确匹配，再做包含匹配，避免「日期」抢了「交易时间」
        for pass in 0..<2 {
            for (kind, hints) in columnHints where map[kind] == nil {
                for (idx, cell) in lowered.enumerated() {
                    if map.values.contains(idx) || cell.isEmpty { continue }
                    let hit = hints.contains { h in
                        let n = normalize(h)
                        return pass == 0 ? cell == n : cell.contains(n)
                    }
                    if hit {
                        map[kind] = idx
                        break
                    }
                }
            }
        }
        return map
    }

    static func parse(text: String) -> ImportResult {
        var result = ImportResult()
        let table = CSV.rows(from: text)
        guard let header = table.first, table.count > 1 else {
            result.errors.append("文件是空的，或者只有表头没有数据行")
            return result
        }

        let map = mapColumns(header)

        // 双金额列格式：一列「支出」一列「收入」
        var expenseCol: Int? = nil
        var incomeCol: Int? = nil
        if map[.amount] == nil {
            for (idx, cell) in header.enumerated() {
                let n = normalize(cell)
                if n.contains("支出") { expenseCol = idx }
                if n.contains("收入") { incomeCol = idx }
            }
        }

        guard map[.date] != nil || map[.amount] != nil || expenseCol != nil || incomeCol != nil else {
            result.errors.append("认不出表头。至少要有「日期」或「金额」列。\n当前列名：" + header.prefix(8).joined(separator: "、"))
            return result
        }

        let formatters = makeDateFormatters()

        for (offset, cells) in table.dropFirst().enumerated() {
            let rowNumber = offset + 2

            func cell(_ k: FieldKind) -> String? {
                guard let i = map[k], i < cells.count else { return nil }
                let v = cells[i].trimmingCharacters(in: .whitespacesAndNewlines)
                return v.isEmpty ? nil : v
            }

            // —— 日期
            var date = Date()
            if let ds = cell(.date) {
                guard let d = parseDate(ds, formatters: formatters) else {
                    result.skipped += 1
                    if result.errors.count < 5 { result.errors.append("第 \(rowNumber) 行日期看不懂：\(ds)") }
                    continue
                }
                date = d
            }

            // —— 金额与方向
            var amount: Double? = nil
            var type: EntryType = .expense

            if let es = cell(.amount) {
                let cleaned = es
                    .replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: "¥", with: "")
                    .replacingOccurrences(of: "￥", with: "")
                    .replacingOccurrences(of: "$", with: "")
                    .replacingOccurrences(of: "元", with: "")
                    .replacingOccurrences(of: " ", with: "")
                if let v = Double(cleaned) {
                    amount = abs(v)
                    // 约定：负数=支出；带 + 号或显式正号=收入；其余靠类型列决定
                    if v < 0 { type = .expense }
                    if cleaned.hasPrefix("+") { type = .income }
                } else {
                    let digits = cleaned.filter { "0123456789.-".contains($0) }
                    if let v = Double(digits), v != 0 {
                        amount = abs(v)
                        if v < 0 { type = .expense }
                        if cleaned.hasPrefix("+") { type = .income }
                    }
                }
            } else if expenseCol != nil || incomeCol != nil {
                func num(_ idx: Int?) -> Double {
                    guard let idx, idx < cells.count else { return 0 }
                    let raw = cells[idx].trimmingCharacters(in: .whitespaces)
                    if raw.isEmpty || raw == "-" || raw == "—" { return 0 }
                    let s = raw.filter { "0123456789.".contains($0) }
                    return Double(s) ?? 0
                }
                let e = num(expenseCol)
                let i = num(incomeCol)
                if i > 0 { amount = i; type = .income }
                else if e > 0 { amount = e }
            }

            guard let amt = amount, amt > 0 else {
                result.skipped += 1
                if result.errors.count < 5 { result.errors.append("第 \(rowNumber) 行没有有效金额") }
                continue
            }

            // —— 文本方向列
            if let ts = cell(.type) {
                let n = normalize(ts)
                if n.contains("收入") || n.contains("income") || n == "收" || n.contains("入") {
                    type = .income
                } else if n.contains("支出") || n.contains("expense") || n.contains("出") {
                    type = .expense
                }
            }

            // —— 分类
            let rawCat = cell(.category) ?? ""
            let catName = mapCategory(rawCat, type: type)

            // —— 备注
            var note = cell(.note) ?? ""
            if !rawCat.isEmpty && normalize(note) == normalize(rawCat) { note = "" }
            if normalize(note) == normalize(catName) { note = "" }
            if note.count > 60 { note = String(note.prefix(60)) }

            result.previewRows.append(ParsedRow(type: type,
                                               amount: (amt * 100).rounded() / 100,
                                               categoryName: catName,
                                               note: note,
                                               date: date))
            result.totalParsed += 1
        }
        return result
    }

    /// 分类名归一。收入/支出各有一份「其他」时靠 type 区分。
    static func mapCategory(_ raw: String, type: EntryType) -> String {
        let key = normalize(raw)
        if key.isEmpty {
            return type == .income ? "其他" : "其他"
        }
        for (target, aliases) in categoryAliases {
            for a in aliases where key.contains(normalize(a)) {
                // 收入行不该被归到纯支出的分类
                if type == .income && ["餐饮", "交通", "购物", "日用", "房租", "水电", "通讯", "娱乐", "医疗", "学习", "人情", "旅行"].contains(target) {
                    continue
                }
                if type == .expense && ["工资", "奖金", "兼职", "报销"].contains(target) {
                    continue
                }
                return target
            }
        }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "其他" : String(trimmed.prefix(10))
    }

    // MARK: 日期
    static func makeDateFormatters() -> [DateFormatter] {
        let patterns = [
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
            "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm", "yyyy/MM/dd",
            "yyyy.MM.dd", "yyyy年M月d日", "yyyy年M月d日 HH:mm", "yyyyMMdd",
            "M/d/yyyy", "MM/dd/yyyy", "yyyy-M-d", "dd/MM/yyyy"
        ]
        return patterns.map { p in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            f.dateFormat = p
            return f
        }
    }

    static func parseDate(_ s: String, formatters: [DateFormatter]) -> Date? {
        let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for f in formatters {
            if let d = f.date(from: cleaned) { return d }
        }
        if let cut = cleaned.firstIndex(where: { $0 == " " || $0 == "T" }) {
            let head = String(cleaned[cleaned.startIndex..<cut])
            for f in formatters {
                if let d = f.date(from: head) { return d }
            }
        }
        return nil
    }
}
