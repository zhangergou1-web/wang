import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var showPicker = false
    @State private var fileName = ""
    @State private var rawText = ""
    @State private var parsed: [ParsedRow] = []
    @State private var preview: ImportResult?
    @State private var errorText: String?
    @State private var done: ImportResult?
    @State private var skipDuplicates = true
    @State private var showPaste = false
    @State private var pasteText = ""
    @State private var isParsing = false
    @State private var parseNote: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                            Text(fileName.isEmpty ? "从「文件」中选择 CSV" : fileName)
                                .lineLimit(1)
                            Spacer()
                            if !fileName.isEmpty {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }

                    Button {
                        readClipboard()
                    } label: {
                        Label("从剪贴板读取", systemImage: "doc.on.clipboard")
                    }

                    Button {
                        showPaste = true
                    } label: {
                        Label("粘贴 CSV 文本", systemImage: "text.cursor")
                    }
                } header: {
                    Text("三种方式，任选一种")
                } footer: {
                    Text("如果系统文件选择器点了没反应，用下面两种。")
                }

                if isParsing {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在解析 \(rawText.count) 个字符…")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                if let err = errorText {
                    Section {
                        Text(err)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = err
                            errorText = err + "\n\n（已复制，可直接发给我）"
                        } label: {
                            Label("复制这段诊断信息", systemImage: "doc.on.doc")
                        }
                    } header: {
                        Text("没有解析出数据")
                    }
                }

                if let p = preview, !p.previewRows.isEmpty {
                    Section {
                        Toggle("跳过与现有记录重复的条目", isOn: $skipDuplicates)
                        ForEach(Array(p.previewRows.prefix(30).enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 10) {
                                Text(store.existingCategoryID(named: row.categoryName, type: row.type)
                                     .flatMap { store.category($0)?.icon } ?? Importer.fallbackIcon(row.categoryName))
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.categoryName).font(.subheadline)
                                    Text("\(row.date.formatted(date: .abbreviated, time: .omitted))  \(row.note)")
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text((row.type == .income ? "+" : "-") + row.amount.moneyText)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(row.type == .income ? .green : .primary)
                            }
                        }
                        if p.previewRows.count > 30 {
                            Text("…… 还有 \(p.previewRows.count - 30) 条")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("预览（共 \(p.previewRows.count) 条）")
                    } footer: {
                        if !p.errors.isEmpty {
                            Text(p.errors.joined(separator: "\n"))
                        }
                    }

                    Section {
                        Button {
                            let r = store.commitImport(p.previewRows, skipDuplicates: skipDuplicates)
                            done = r
                            preview = nil
                            parsed = []
                            rawText = ""
                        } label: {
                            Text("导入 \(p.previewRows.count) 条记录").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if let d = done {
                    Section {
                        Label(d.summary, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section {
                    DisclosureGroup("支持哪些格式？") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("自动识别常见列名：日期 / 时间 / 交易时间，金额 / 收支金额，分类 / 类别，备注 / 说明 / 商家，类型 / 收支。")
                            Text("也支持「支出」「收入」分成两列的格式。")
                            Text("分隔符自动判断（逗号 / 制表符 / 分号），支持 Excel 导出的带 BOM 的 CSV。")
                            Text("分类名会自动归并到本 App 的分类，认不出的会新建一个分类保留原名字。")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    Button("查看示例格式") {
                        errorText = "示例：\n日期,类型,分类,金额,备注\n2026-01-05,支出,餐饮,32.50,午饭\n2026-01-06,收入,工资,12000,1月工资"
                    }
                }
            }
            .navigationTitle("导入数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showPicker,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .text, .tabSeparatedText],
                          allowsMultipleSelection: false) { result in
                handlePick(result)
            }
            .sheet(isPresented: $showPaste) {
                PasteSheet(text: $pasteText) {
                    applyPaste()
                }
            }
        }
    }

    private func handlePick(_ result: Result<[URL], Error>) {
        errorText = nil
        preview = nil
        done = nil
        switch result {
        case .failure(let e):
            errorText = "读取失败：\(e.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            fileName = url.lastPathComponent
            var text: String?
            // 先试 UTF-8，再试 GB18030（国内软件常导出 GBK）
            if let t = try? String(contentsOf: url, encoding: .utf8) {
                text = t
            } else if let data = try? Data(contentsOf: url),
                      let t = String(data: data, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(
                        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))) {
                text = t
            }

            guard let content = text else {
                errorText = "文件编码无法识别，请在导出时选择 UTF-8"
                return
            }
            rawText = content
            parseNow()
        }
    }

    private func parseNow() {
        let source = rawText
        guard !source.isEmpty else { return }

        // 粗略估算行数，超限直接拒绝，避免内存爆炸
        let lineCount = source.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        guard lineCount <= 100_000 else {
            errorText = "文本有 \(lineCount) 行，超过 10 万行上限。请拆分后再导入。"
            return
        }

        // 大文件在后台解析，避免阻塞主线程导致卡死
        isParsing = true
        errorText = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Importer.parse(text: source)
            DispatchQueue.main.async {
                isParsing = false
                parsed = r.previewRows
                if r.previewRows.isEmpty {
                    errorText = r.errors.isEmpty ? "没有解析出任何记录" : r.errors.joined(separator: "\n")
                } else {
                    preview = r
                    // 预览只保留前面一部分，真实导入用全部
                    if let last = r.errors.last {
                        parseNote = last
                    }
                }
            }
        }
    }

    private func readClipboard() {
        errorText = nil
        preview = nil
        done = nil
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            errorText = "剪贴板里没有文字"
            return
        }
        fileName = "来自剪贴板"
        rawText = text
        parseNow()
    }

    private func applyPaste() {
        let text = pasteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        errorText = nil
        preview = nil
        done = nil
        fileName = "粘贴的文本"
        rawText = text
        parseNow()
        showPaste = false
    }
}
