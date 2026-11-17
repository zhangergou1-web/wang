import SwiftUI

struct EntryEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    let entry: Entry?   // nil = 新建

    @State private var type: EntryType = .expense
    @State private var amountText = ""
    @State private var categoryID: UUID?
    @State private var note = ""
    @State private var date = Date()
    @State private var showDeleteConfirm = false
    @State private var showNewCategory = false
    @State private var newCatName = ""
    @State private var newCatIcon = "🏷️"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $type) {
                        ForEach(EntryType.allCases) { t in
                            Text(t.title).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { _, _ in
                        // 切换类型后，分类要跟着重置
                        categoryID = store.roots(type).first?.id
                    }

                    HStack {
                        Text("¥").foregroundStyle(.secondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                    }
                    .padding(.vertical, 6)
                }

                Section("分类") {
                    CategoryPicker(type: type, selection: $categoryID)
                    Button {
                        showNewCategory = true
                    } label: {
                        Label("新建分类", systemImage: "plus.circle")
                    }
                }

                Section("备注") {
                    TextField("例如：和朋友吃午饭", text: $note)
                }

                Section("日期") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                }

                if entry != nil {
                    Section {
                        Button("删除这条记录", role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle(entry == nil ? "记一笔" : "编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.bold()
                }
            }
            .alert("删除这条记录？", isPresented: $showDeleteConfirm) {
                Button("删除", role: .destructive) {
                    if let e = entry { store.delete(e) }
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
            .alert("新建分类", isPresented: $showNewCategory) {
                TextField("分类名称", text: $newCatName)
                TextField("图标（一个 emoji）", text: $newCatIcon)
                Button("添加") { addCategory() }
                Button("取消", role: .cancel) { newCatName = "" }
            } message: {
                Text("当前类型：\(type.title)")
            }
            .onAppear(perform: prepare)
        }
    }

    private func prepare() {
        guard let e = entry else {
            categoryID = store.roots(type).first?.id
            return
        }
        type = e.type
        amountText = e.amount == e.amount.rounded() ? String(Int(e.amount)) : String(e.amount)
        categoryID = e.categoryID
        note = e.note
        date = e.date
    }

    private func addCategory() {
        let name = newCatName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let icon = newCatIcon.isEmpty ? "🏷️" : String(newCatIcon.prefix(2))
        store.addCategory(name: name, icon: icon, type: type, parent: nil)
        newCatName = ""
        newCatIcon = "🏷️"
        if let last = store.categories.last { categoryID = last.id }
    }

    private func save() {
        let normalized = amountText.replacingOccurrences(of: ",", with: "")
        guard let amount = Double(normalized), amount > 0 else {
            dismiss()   // 金额无效时不保存
            return
        }
        guard let cid = categoryID else { return }

        if var e = entry {
            e.type = type
            e.amount = (amount * 100).rounded() / 100
            e.categoryID = cid
            e.note = note.trimmingCharacters(in: .whitespaces)
            e.date = date
            store.update(e)
        } else {
            store.add(Entry(type: type, amount: (amount * 100).rounded() / 100,
                            categoryID: cid, note: note.trimmingCharacters(in: .whitespaces),
                            date: date))
        }
        dismiss()
    }
}

// MARK: - 分类选择器（一级 + 二级）
struct CategoryPicker: View {
    @EnvironmentObject var store: Store
    let type: EntryType
    @Binding var selection: UUID?

    var body: some View {
        let roots = store.roots(type)
        let cols = [GridItem(.adaptive(minimum: 82), spacing: 8)]

        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(roots) { c in
                Button {
                    selection = c.id
                } label: {
                    VStack(spacing: 4) {
                        Text(c.icon).font(.title3)
                        Text(c.name).font(.caption).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selection == c.id ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selection == c.id ? Color.accentColor : .clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)

        // 二级分类
        if let root = store.root(of: selection ?? UUID()), !store.children(of: root.id).isEmpty {
            Menu {
                ForEach(store.children(of: root.id)) { child in
                    Button("\(child.icon) \(child.name)") { selection = child.id }
                }
                Button("不使用二级分类") { selection = root.id }
            } label: {
                HStack {
                    Text("二级分类")
                    Spacer()
                    Text(store.category(selection ?? UUID())?.name ?? "")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
            }
        }
    }
}
