import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var month = Date()
    @State private var tab = 0
    @State private var pickedDay: Int? = nil
    @State private var editing: Entry? = nil
    @State private var showEditor = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    MonthHeader(month: $month, pickedDay: $pickedDay)
                    SummaryCard(month: month)
                    DailyChart(month: month, pickedDay: $pickedDay)
                    if tab == 0 {
                        EntryList(month: month, pickedDay: pickedDay) { e in editing = e }
                    } else {
                        StatsView(month: month)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("小账本")
        .navigationBarTitleDisplayMode(.large)
        .overlay(alignment: .bottom) { BottomBar(tab: $tab) }
        .sheet(item: $editing) { e in EntryEditor(entry: e) }
        .sheet(isPresented: $showEditor) { EntryEditor(entry: nil) }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showEditor = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
        }
    }
}

// MARK: - 月份切换
struct MonthHeader: View {
    @Binding var month: Date
    @Binding var pickedDay: Int?

    var body: some View {
        HStack {
            Button { month = month.addingMonths(-1); pickedDay = nil } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(month.monthTitle).font(.headline)
            Spacer()
            Button { month = month.addingMonths(1); pickedDay = nil } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - 汇总卡片
struct SummaryCard: View {
    @EnvironmentObject var store: Store
    let month: Date

    var body: some View {
        let income = store.total(.income, in: month)
        let expense = store.total(.expense, in: month)
        let net = income - expense

        VStack(alignment: .leading, spacing: 10) {
            Text("本月结余").font(.caption).foregroundStyle(.secondary)
            Text((net < 0 ? "-¥" : "¥") + net.moneyText)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(net < 0 ? .red : .primary)
            HStack(spacing: 10) {
                MiniStat(title: "收入", value: income, color: .green)
                MiniStat(title: "支出", value: expense, color: .red)
                ExpenseBudgetMini(month: month)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct MiniStat: View {
    let title: String
    let value: Double
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text("¥" + value.moneyText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - 预算小条
struct ExpenseBudgetMini: View {
    @EnvironmentObject var store: Store
    let month: Date

    var body: some View {
        let expense = store.total(.expense, in: month)
        let total = store.budget.total ?? 0
        VStack(alignment: .leading, spacing: 2) {
            Text("预算剩余").font(.caption2).foregroundStyle(.secondary)
            if total > 0 {
                let left = total - expense
                Text((left < 0 ? "-¥" : "¥") + left.moneyText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(left < 0 ? .red : .primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text("未设置").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - 每日柱状图
struct DailyChart: View {
    @EnvironmentObject var store: Store
    let month: Date
    @Binding var pickedDay: Int?

    var body: some View {
        let bars = dailyExpenses()
        let maxV = max(bars.max() ?? 0, 1)

        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<bars.count, id: \.self) { i in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(pickedDay == nil || pickedDay == i + 1 ? 0.9 : 0.25))
                        .frame(height: max(3, CGFloat(bars[i] / maxV) * 76))
                    Text("\(i + 1)")
                        .font(.system(size: 9))
                        .foregroundStyle(pickedDay == i + 1 ? Color.accentColor : .secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    pickedDay = pickedDay == i + 1 ? nil : i + 1
                }
            }
        }
        .frame(height: 92, alignment: .bottom)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var days: Int {
        Calendar.current.range(of: .day, in: .month, for: month)?.count ?? 30
    }

    /// 当月每天支出合计（下标 0 = 1 号）
    private func dailyExpenses() -> [Double] {
        let cal = Calendar.current
        var sums = [Double](repeating: 0, count: days)
        for e in store.entries(in: month) {
            guard e.type == .expense else { continue }
            let d = cal.component(.day, from: e.date)
            if d >= 1 && d <= sums.count { sums[d - 1] += e.amount }
        }
        return sums
    }
}

// MARK: - 明细列表
struct EntryList: View {
    @EnvironmentObject var store: Store
    let month: Date
    let pickedDay: Int?
    var onTap: (Entry) -> Void

    var body: some View {
        let rowEntries: [Entry] = {
            var list = store.entries(in: month)
            if let d = pickedDay {
                list = list.filter { Calendar.current.component(.day, from: $0.date) == d }
            }
            return list.sorted {
                $0.date != $1.date ? $0.date > $1.date : $0.createdAt > $1.createdAt
            }
        }()

        LazyVStack(spacing: 0) {
            if rowEntries.isEmpty {
                Text(pickedDay == nil ? "本月还没有记录" : "这一天没有记账")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                ForEach(grouped(rowEntries), id: \.key) { group in
                    HStack {
                        Text(group.key).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.top, 10)
                    ForEach(group.items) { e in
                        EntryRow(entry: e)
                            .contentShape(Rectangle())
                            .onTapGesture { onTap(e) }
                        Divider().padding(.leading, 60)
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    struct Group { let key: String; let items: [Entry] }

    private func grouped(_ list: [Entry]) -> [Group] {
        var order: [String] = []
        var map: [String: [Entry]] = [:]
        for e in list {
            let k = e.date.dayLabel
            if map[k] == nil { order.append(k) }
            map[k, default: []].append(e)
        }
        return order.map { Group(key: $0, items: map[$0] ?? []) }
    }
}

struct EntryRow: View {
    @EnvironmentObject var store: Store
    let entry: Entry

    var body: some View {
        HStack(spacing: 12) {
            Text(store.category(entry.categoryID)?.icon ?? "🏷️")
                .font(.title3)
                .frame(width: 38, height: 38)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text(store.category(entry.categoryID)?.name ?? "未知")
                    .font(.subheadline.weight(.medium))
                Text(entry.note.isEmpty ? entry.type.title : entry.note)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text((entry.type == .income ? "+" : "-") + entry.amount.moneyText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(entry.type == .income ? .green : .primary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: - 底部切换
struct BottomBar: View {
    @Binding var tab: Int
    var body: some View {
        HStack(spacing: 0) {
            Button { tab = 0 } label: {
                Label("明细", systemImage: "list.bullet").frame(maxWidth: .infinity)
            }
            Button { tab = 1 } label: {
                Label("统计", systemImage: "chart.bar.xaxis").frame(maxWidth: .infinity)
            }
        }
        .font(.footnote)
        .padding(.top, 8)
        .padding(.horizontal, 40)
        .background(.regularMaterial)
    }
}
