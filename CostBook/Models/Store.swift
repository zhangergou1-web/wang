import Foundation
import SwiftUI

// MARK: - 记录类型
enum EntryType: String, Codable, CaseIterable, Identifiable {
    case expense, income
    var id: String { rawValue }
    var title: String { self == .expense ? "支出" : "收入" }
}

// MARK: - 一条账目
struct Entry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var type: EntryType
    var amount: Double
    var categoryID: UUID
    var note: String = ""
    var date: Date
    var createdAt: Date = Date()
}

// MARK: - 分类（支持一级/二级）
struct Category: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var icon: String
    var type: EntryType
    var parentID: UUID? = nil
}

// MARK: - 预算
struct Budget: Codable {
    var total: Double? = nil               // 每月总预算
    var perCategory: [String: Double] = [:] // categoryID.uuidString -> 预算
}

// MARK: - 持久化
@MainActor
final class Store: ObservableObject {
    /// 批量修改时置 true，避免每次变更都写盘
    private var suspendPersist = false

    @Published var entries: [Entry] = [] { didSet { persist() } }
    @Published var categories: [Category] = [] { didSet { persist() } }
    @Published var budget = Budget() { didSet { persist() } }

    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("costbook.json")
        load()
    }

    // MARK: 读写
    private struct Snapshot: Codable {
        var entries: [Entry]
        var categories: [Category]
        var budget: Budget
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            seed()
            return
        }
        entries = snap.entries
        categories = snap.categories
        budget = snap.budget
    }

    private func persist() {
        if suspendPersist { return }
        let snap = Snapshot(entries: entries, categories: categories, budget: budget)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func seed() {
        categories = [
            Category(name: "餐饮", icon: "🍜", type: .expense),
            Category(name: "交通", icon: "🚇", type: .expense),
            Category(name: "购物", icon: "🛍️", type: .expense),
            Category(name: "日用", icon: "🧴", type: .expense),
            Category(name: "房租", icon: "🏠", type: .expense),
            Category(name: "水电", icon: "💡", type: .expense),
            Category(name: "通讯", icon: "📱", type: .expense),
            Category(name: "娱乐", icon: "🎮", type: .expense),
            Category(name: "医疗", icon: "💊", type: .expense),
            Category(name: "学习", icon: "📚", type: .expense),
            Category(name: "人情", icon: "🎁", type: .expense),
            Category(name: "旅行", icon: "✈️", type: .expense),
            Category(name: "其他", icon: "📦", type: .expense),
            Category(name: "工资", icon: "💰", type: .income),
            Category(name: "奖金", icon: "🏆", type: .income),
            Category(name: "兼职", icon: "🛠️", type: .income),
            Category(name: "理财", icon: "📈", type: .income),
            Category(name: "红包", icon: "🧧", type: .income),
            Category(name: "报销", icon: "🧾", type: .income),
            Category(name: "其他", icon: "📦", type: .income)
        ]
    }

    // MARK: 便捷访问
    func category(_ id: UUID) -> Category? { categories.first { $0.id == id } }
    func roots(_ type: EntryType) -> [Category] { categories.filter { $0.type == type && $0.parentID == nil } }
    func children(of id: UUID) -> [Category] { categories.filter { $0.parentID == id } }

    /// 选中项所属的一级分类（本身就是一级则返回自己）
    func root(of id: UUID) -> Category? {
        guard let c = category(id) else { return nil }
        return c.parentID.flatMap { category($0) } ?? c
    }

    func entries(in month: Date) -> [Entry] {
        entries.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    func total(_ type: EntryType, in month: Date) -> Double {
        entries(in: month).filter { $0.type == type }.reduce(0) { $0 + $1.amount }
    }

    func byCategory(_ type: EntryType, in month: Date) -> [(Category, Double)] {
        var sums: [UUID: Double] = [:]
        for e in entries(in: month) where e.type == type {
            // 二级分类的钱归到一级分类
            let root = category(e.categoryID)?.parentID ?? e.categoryID
            sums[root, default: 0] += e.amount
        }
        return sums.compactMap { id, v in category(id).map { ($0, v) } }
            .sorted { $0.1 > $1.1 }
    }

    func add(_ entry: Entry) { entries.append(entry) }
    func update(_ entry: Entry) {
        if let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i] = entry }
    }
    func delete(_ entry: Entry) { entries.removeAll { $0.id == entry.id } }

    func addCategory(name: String, icon: String, type: EntryType, parent: UUID?) {
        categories.append(Category(name: name, icon: icon, type: type, parentID: parent))
    }

    // MARK: - 导入
    /// 找出或新建分类，返回 ID
    func categoryID(named name: String, type: EntryType) -> UUID {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        if let hit = categories.first(where: { $0.type == type && $0.name.lowercased() == key }) {
            return hit.id
        }
        // 也在二级分类里找
        if let hit = categories.first(where: { $0.type == type && $0.name.lowercased() == key && $0.parentID != nil }) {
            return hit.id
        }
        let icon = CategoryIcon.guess(name)
        let c = Category(name: name, icon: icon, type: type)
        categories.append(c)
        return c.id
    }


    /// 只查不建，用于预览显示图标
    func existingCategoryID(named name: String, type: EntryType) -> UUID? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        return categories.first { $0.type == type && $0.name.lowercased() == key }?.id
    }

    /// 提交导入：建立分类、跳过重复、写入
    @discardableResult
    func commitImport(_ rows: [ParsedRow], skipDuplicates: Bool = true) -> ImportResult {
        var result = ImportResult()

        // 先把分类索引建好，避免循环内反复线性查找
        var catIndex: [String: UUID] = [:]
        for c in categories {
            catIndex["\(c.type.rawValue)|\(c.name.lowercased())"] = c.id
        }
        func catID(_ name: String, _ type: EntryType) -> UUID {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let key = "\(type.rawValue)|\(trimmed.lowercased())"
            if let hit = catIndex[key] { return hit }
            let new = Category(name: trimmed, icon: CategoryIcon.guess(trimmed), type: type)
            categories.append(new)
            catIndex[key] = new.id
            return new.id
        }

        var existing = Set<String>()
        if skipDuplicates {
            for e in entries {
                let name = category(e.categoryID)?.name ?? ""
                existing.insert("\(Int(e.date.timeIntervalSince1970 / 60))|\(e.type.rawValue)|\(e.amount)|\(name)|\(e.note)")
            }
        }

        var newEntries: [Entry] = []
        newEntries.reserveCapacity(rows.count)
        var seen = Set<String>()

        for row in rows {
            let sig = row.signature
            if skipDuplicates && (existing.contains(sig) || seen.contains(sig)) {
                result.duplicates += 1
                continue
            }
            seen.insert(sig)
            let cid = catID(row.categoryName, row.type)
            newEntries.append(Entry(type: row.type, amount: row.amount, categoryID: cid,
                                    note: row.note, date: row.date))
            result.added += 1
        }

        // 关键：一次性合并 + 只落盘一次，避免逐条写文件导致 O(n²)
        suspendPersist = true
        entries.append(contentsOf: newEntries)
        suspendPersist = false
        persist()

        return result
    }
    func deleteCategory(_ cat: Category) {
        categories.removeAll { $0.id == cat.id || $0.parentID == cat.id }
    }
}
