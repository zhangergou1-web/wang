import SwiftUI

struct StatsView: View {
    @EnvironmentObject var store: Store
    let month: Date
    @State private var mode: EntryType = .expense
    @State private var exportURL: URL?
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 14) {
            Picker("", selection: $mode) {
                Text("支出").tag(EntryType.expense)
                Text("收入").tag(EntryType.income)
            }
            .pickerStyle(.segmented)

            let rows = store.byCategory(mode, in: month)
            let total = rows.reduce(0) { $0 + $1.1 }
            let maxV = rows.first?.1 ?? 1

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(mode.title + "合计")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Text("¥" + total.moneyText).font(.headline)
                }
                if rows.isEmpty {
                    Text("本月没有数据")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        let cat = row.0
                        let value = row.1
                        VStack(spacing: 5) {
                            HStack {
                                Text("\(cat.icon) \(cat.name)")
                                    .font(.subheadline)
                                Text("\(Int(value / max(total, 0.01) * 100))%")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text("¥" + value.moneyText)
                                    .font(.subheadline.weight(.semibold))
                            }
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3.5)
                                    .fill(Color(.tertiarySystemGroupedBackground))
                                    .overlay(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3.5)
                                            .fill(Color.accentColor)
                                            .frame(width: max(4, geo.size.width * value / maxV))
                                    }
                            }
                            .frame(height: 7)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 8) {
                if let url = exportURL {
                    ShareLink(item: url) {
                        Label("分享 CSV", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        exportURL = CSVExporter.write(from: store)
                    } label: {
                        Label("导出 CSV", systemImage: "tablecells")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    showSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

// MARK: - 设置：预算 / 分类 / 锁
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lockEnabled") private var lockEnabled = false

    @State private var totalBudgetText = ""
    @State private var newName = ""
    @State private var newIcon = "🏷️"
    @State private var newType: EntryType = .expense
    @State private var showImport = false

    var body: some View {
        NavigationStack {
            Form {
                Section("每月总预算") {
                    HStack {
                        Text("¥").foregroundStyle(.secondary)
                        TextField("不设置则留空", text: $totalBudgetText)
                            .keyboardType(.decimalPad)
                    }
                    .onAppear {
                        if let t = store.budget.total { totalBudgetText = String(Int(t)) }
                    }
                    .onChange(of: totalBudgetText) { _, v in
                        store.budget.total = Double(v)
                    }
                }

                Section {
                    Button {
                        showImport = true
                    } label: {
                        HStack {
                            Label("从其他记账软件导入", systemImage: "square.and.arrow.down")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                } footer: {
                    Text("支持 CSV，自动识别常见列名，可预览后确认。")
                }

                Section("分类预算") {
                    ForEach(store.roots(.expense)) { c in
                        HStack {
                            Text("\(c.icon) \(c.name)")
                            Spacer()
                            TextField("不限", text: Binding(
                                get: {
                                    if let v = store.budget.perCategory[c.id.uuidString] { return String(Int(v)) }
                                    return ""
                                },
                                set: { newValue in
                                    store.budget.perCategory[c.id.uuidString] = Double(newValue)
                                }
                            ))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        }
                    }
                }

                Section("分类管理") {
                    ForEach(EntryType.allCases) { t in
                        DisclosureGroup(t.title) {
                            ForEach(store.roots(t)) { c in
                                HStack {
                                    Text("\(c.icon) \(c.name)")
                                    Spacer()
                                    Button(role: .destructive) {
                                        store.deleteCategory(c)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    HStack {
                        TextField("图标", text: $newIcon).frame(width: 50)
                        TextField("新分类名称", text: $newName)
                        Picker("", selection: $newType) {
                            Text("支出").tag(EntryType.expense)
                            Text("收入").tag(EntryType.income)
                        }
                        .labelsHidden()
                        .frame(width: 70)
                        Button("添加") {
                            let n = newName.trimmingCharacters(in: .whitespaces)
                            guard !n.isEmpty else { return }
                            store.addCategory(name: n, icon: newIcon.isEmpty ? "🏷️" : newIcon,
                                              type: newType, parent: nil)
                            newName = ""
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section {
                    Toggle("启动时用 Face ID / 密码锁定", isOn: $lockEnabled)
                } footer: {
                    Text("数据仅保存在本机，不会上传到任何服务器。")
                }
            }
            .sheet(isPresented: $showImport) { ImportView() }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
