import SwiftUI
#if os(iOS)
import PhotosUI
#endif

struct ItemEditScreen: View {
    @State private var showDiscard = false
    @State private var saveError: String?
    @State private var isImportingPhotos = false
    @State private var isImportingSizeChart = false
    @State private var isLeaving = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var skinManager: SkinManager
    @StateObject private var viewModel = ItemEditViewModel()

    var itemId: Int64 = 0
    var defaultStatus: ItemStatus = .owned
    #if os(iOS)
    @State private var chartPickerItem: PhotosPickerItem?
    @State private var chartImportTask: Task<Void, Never>?
    @State private var chartImportId: UUID?
    #endif

    private var cardBackground: Color {
        colorScheme == .dark ? skinManager.current.cardColorDark : skinManager.current.cardColor
    }

    var body: some View {
        Form {
            Section {
                TextField("服饰名称（必填）", text: $viewModel.name)
                TextField("描述（选填）", text: $viewModel.description, axis: .vertical)
                    .lineLimit(2...5)
                SearchableRecordPicker(title: "品牌", options: viewModel.brands.map { PickerRecord(id: $0.id, name: $0.name) }, selection: $viewModel.brandId)
                SearchableRecordPicker(title: "分类", options: viewModel.categories.map { PickerRecord(id: $0.id, name: $0.name) }, selection: $viewModel.categoryId)
            } header: {
                Text("基本信息")
            }
            .lolitaCollectionRowInsets()
            .listRowBackground(cardBackground)

            Section {
                Picker("状态", selection: $viewModel.status) {
                    Text("已拥有").tag(ItemStatus.owned)
                    Text("想要").tag(ItemStatus.wished)
                    Text("待尾款").tag(ItemStatus.pendingBalance)
                }
                if viewModel.status == .wished {
                    Picker("心愿优先级", selection: $viewModel.priority) {
                        Text("高").tag(ItemPriority.high)
                        Text("中").tag(ItemPriority.medium)
                        Text("低").tag(ItemPriority.low)
                    }
                }
                Picker("所属套装", selection: $viewModel.coordinateId) {
                    Text("未归入套装").tag(nil as Int64?)
                    ForEach(viewModel.coordinates, id: \.id) { Text($0.name).tag($0.id as Int64?) }
                }
                Picker("存放位置", selection: $viewModel.locationId) {
                    Text("未设置").tag(nil as Int64?)
                    ForEach(viewModel.locations, id: \.id) { location in
                        Text(location.name).tag(location.id as Int64?)
                    }
                }
                Picker("购买渠道", selection: $viewModel.source) {
                    Text("未设置").tag("")
                    ForEach(viewModel.sources, id: \.id) { Text($0.name).tag($0.name) }
                }
            } header: {
                Text("收纳与购买")
            }
            .lolitaCollectionRowInsets()
            .listRowBackground(cardBackground)

            Section {
                Picker("风格", selection: $viewModel.style) {
                    Text("未设置").tag("")
                    ForEach(viewModel.styles, id: \.id) { Text($0.name).tag($0.name) }
                }
                EditSeasonSelection(seasons: viewModel.seasons.map(\.name), selection: $viewModel.season)
                LabeledContent("尺码") {
                    TextField("如 S、M、均码", text: $viewModel.size)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("款式信息")
            }
            .lolitaCollectionRowInsets()
            .listRowBackground(cardBackground)

            Section("颜色") {
                EditColorSelection(colors: MatchingEngine.colors, selectedColors: $viewModel.colors)
            }
            .lolitaCollectionRowInsets()
            .listRowBackground(cardBackground)

            EditPhotosSection(
                title: "服饰照片",
                imageUrls: viewModel.imageUrls,
                showsCoverLabel: true,
                onAddData: { data in
                    guard !isLeaving else { return }
                    viewModel.addImageData(data)
                },
                onRemove: viewModel.removeImage,
                onImportingChanged: { isImportingPhotos = $0 }
            )

            Section("尺码表") {
                if let path = viewModel.sizeChartImageUrl {
                    LolitaShimmerImage(url: ImageFileHelper.fileURL(for: path), contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipped()
                    Button("移除尺码表", role: .destructive) { viewModel.removeSizeChart() }
                }
                #if os(iOS)
                let chartPickerTitle = viewModel.sizeChartImageUrl == nil ? "添加尺码表" : "更换尺码表"
                let showsChartImportProgress = isImportingSizeChart
                PhotosPicker(selection: $chartPickerItem, matching: .images) {
                    HStack {
                        Label(chartPickerTitle, systemImage: "photo")
                        Spacer()
                        if showsChartImportProgress { ProgressView() }
                    }
                }
                .disabled(isImportingSizeChart)
                .onChange(of: chartPickerItem) { _, item in
                    guard let item else { return }
                    chartImportTask?.cancel()
                    let importId = UUID()
                    chartImportId = importId
                    isImportingSizeChart = true
                    chartImportTask = Task { @MainActor in
                        defer {
                            if chartImportId == importId {
                                chartImportTask = nil
                                chartImportId = nil
                                isImportingSizeChart = false
                                chartPickerItem = nil
                            }
                        }
                        let data = try? await item.loadTransferable(type: Data.self)
                        guard !Task.isCancelled, chartImportId == importId, !isLeaving else { return }
                        if let data { viewModel.setSizeChart(data: data) }
                    }
                }
                #endif
            }
            .lolitaCollectionRowInsets()
            .listRowBackground(cardBackground)
        }
        #if os(iOS)
        .contentMargins(.horizontal, 12, for: .scrollContent)
        #endif
        .disabled(viewModel.isSaving)
        .scrollDismissesKeyboard(.interactively)
        .interactiveDismissDisabled(viewModel.isSaving || viewModel.hasChanges || isImportingPhotos || isImportingSizeChart)
        .confirmationDialog("放弃未保存的更改？", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("放弃更改", role: .destructive) {
                guard !viewModel.isSaving else { return }
                discardAndDismiss()
            }
            .disabled(viewModel.isSaving)
            Button("继续编辑", role: .cancel) {}
        }
        .onDisappear {
            #if os(iOS)
            chartImportTask?.cancel()
            chartImportTask = nil
            chartImportId = nil
            isImportingSizeChart = false
            chartPickerItem = nil
            #endif
        }
        .alert("保存失败", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("确定", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .lolitaNavBar(title: itemId == 0 ? "新增服饰" : "编辑服饰", showBack: true, onBack: {
            guard !viewModel.isSaving else { return }
            if viewModel.hasChanges || isImportingPhotos || isImportingSizeChart { showDiscard = true }
            else { discardAndDismiss() }
        })
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    guard !viewModel.isSaving, !isImportingPhotos, !isImportingSizeChart else { return }
                    Task {
                        do {
                            try await viewModel.save()
                            dismiss()
                        } catch { saveError = userFacingError(error) }
                    }
                }
                .disabled(viewModel.name.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSaving || isImportingPhotos || isImportingSizeChart)
            }
        }
        #endif
        .task { await viewModel.load(itemId: itemId, defaultStatus: defaultStatus) }
    }

    private func discardAndDismiss() {
        guard !viewModel.isSaving else { return }
        isLeaving = true
        #if os(iOS)
        chartImportTask?.cancel()
        chartImportTask = nil
        chartImportId = nil
        isImportingSizeChart = false
        chartPickerItem = nil
        #endif
        viewModel.discardImages()
        dismiss()
    }
}

struct EditColorSelection: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme

    let colors: [String]
    @Binding var selectedColors: Set<String>
    var allowsCustomColor = true
    @State private var showCustomColor = false
    @State private var customColor = ""

    private var visibleColors: [String] {
        colors + selectedColors.subtracting(Set(colors)).sorted()
    }

    private var accent: Color {
        colorScheme == .dark ? skinManager.current.primaryColorDark : skinManager.current.primaryColor
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 10) {
            ForEach(visibleColors, id: \.self) { color in
                let selected = selectedColors.contains(color)
                Button {
                    if selected { selectedColors.remove(color) }
                    else { selectedColors.insert(color) }
                } label: {
                    HStack(spacing: 4) {
                        if selected { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
                        Text(color).font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .foregroundStyle(selected ? accent : .primary)
                    .background(accent.opacity(selected ? 0.14 : 0.04), in: Capsule())
                    .overlay(Capsule().strokeBorder(accent.opacity(selected ? 0.6 : 0.15)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            if allowsCustomColor { Button { customColor = ""; showCustomColor = true } label: {
                Label("自定义", systemImage: "plus")
                    .font(.subheadline).frame(maxWidth: .infinity, minHeight: 36)
                    .foregroundStyle(accent)
                    .background(accent.opacity(0.04), in: Capsule())
                    .overlay(Capsule().strokeBorder(accent.opacity(0.15)))
            }
            .buttonStyle(.plain) }
        }
        .padding(.vertical, 6)
        .alert("自定义颜色", isPresented: $showCustomColor) {
            TextField("颜色名称", text: $customColor)
            Button("添加") {
                let name = customColor.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { selectedColors.insert(String(name.prefix(30))) }
            }
            Button("取消", role: .cancel) {}
        }
    }
}

struct EditSeasonSelection: View {
    let seasons: [String]
    @Binding var selection: String

    private var selected: Set<String> {
        Set(selection.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("季节（可多选）").font(.subheadline).foregroundStyle(.secondary)
            EditColorSelection(colors: seasons, selectedColors: Binding(get: { selected }, set: { values in
                let known = seasons.filter { values.contains($0) }
                let other = values.subtracting(Set(seasons)).sorted()
                selection = (known + other).joined(separator: ",")
            }), allowsCustomColor: false)
        }
    }
}

struct PickerRecord: Identifiable {
    let id: Int64
    let name: String
}

struct SearchableRecordPicker: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let options: [PickerRecord]
    @Binding var selection: Int64
    @State private var showPicker = false
    @State private var search = ""

    private var filteredOptions: [PickerRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return options.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var cardBackground: Color {
        colorScheme == .dark ? skinManager.current.cardColorDark : skinManager.current.cardColor
    }

    var body: some View {
        Button { search = ""; showPicker = true } label: {
            HStack(spacing: 12) {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(options.first { $0.id == selection }?.name ?? "请选择")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                List {
                    if filteredOptions.isEmpty {
                        ContentUnavailableView(
                            options.isEmpty ? "暂无\(title)" : "未找到\(title)",
                            systemImage: "magnifyingglass",
                            description: Text(options.isEmpty ? "可在设置中管理\(title)" : "试试其他关键词")
                        )
                    } else {
                        ForEach(filteredOptions) { option in
                            Button { selection = option.id; showPicker = false } label: {
                                HStack {
                                    Text(option.name).foregroundStyle(.primary)
                                    Spacer()
                                    if option.id == selection {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                    }
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .lolitaCollectionRowInsets()
                            .listRowBackground(cardBackground)
                        }
                    }
                }
                .searchable(text: $search, prompt: "搜索\(title)")
                .lolitaNavBar(title: "选择\(title)")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showPicker = false } } }
            }
        }
    }
}

struct EditImageStrip: View {
    @EnvironmentObject private var skinManager: SkinManager

    let imageUrls: [String]
    var showsCoverLabel = false
    var aspectRatio: CGFloat = 0.75
    let onRemove: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: skinManager.current.spacingM) {
                ForEach(Array(imageUrls.enumerated()), id: \.offset) { index, path in
                    ImageFrame {
                        LolitaShimmerImage(url: ImageFileHelper.fileURL(for: path))
                            .frame(width: 96, height: 96 / aspectRatio)
                            .clipped()
                            .overlay(alignment: .bottomLeading) {
                                if showsCoverLabel && index == 0 {
                                    Text("封面")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(.black.opacity(0.6), in: Capsule())
                                        .padding(7)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                Button { onRemove(index) } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(.black.opacity(0.6), in: Circle())
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("移除第 \(index + 1) 张照片")
                            }
                    }
                }
            }
            .padding(.vertical, skinManager.current.spacingS)
        }
    }
}

struct EditPhotosSection: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let imageUrls: [String]
    var showsCoverLabel = false
    var aspectRatio: CGFloat = 0.75
    let onAddData: (Data) -> Void
    let onRemove: (Int) -> Void
    var onImportingChanged: (Bool) -> Void = { _ in }

    #if os(iOS)
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var importTask: Task<Void, Never>?
    @State private var importId: UUID?
    #endif

    var body: some View {
        Section {
            if !imageUrls.isEmpty {
                EditImageStrip(
                    imageUrls: imageUrls,
                    showsCoverLabel: showsCoverLabel,
                    aspectRatio: aspectRatio,
                    onRemove: onRemove
                )
            }
            #if os(iOS)
            let showsPhotoImportProgress = isImporting
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 10, matching: .images) {
                HStack {
                    Label("添加照片", systemImage: "photo.badge.plus")
                    Spacer()
                    if showsPhotoImportProgress { ProgressView() }
                }
            }
            .disabled(isImporting)
            .onChange(of: selectedPhotos) { _, photos in
                guard !photos.isEmpty else { return }
                importTask?.cancel()
                let newImportId = UUID()
                importId = newImportId
                isImporting = true
                onImportingChanged(true)
                importTask = Task { @MainActor in
                    defer {
                        if importId == newImportId {
                            importTask = nil
                            importId = nil
                            isImporting = false
                            selectedPhotos = []
                            onImportingChanged(false)
                        }
                    }
                    for photo in photos {
                        let data = try? await photo.loadTransferable(type: Data.self)
                        guard !Task.isCancelled, importId == newImportId else { return }
                        if let data { onAddData(data) }
                    }
                }
            }
            #else
            Label("macOS 暂不支持添加照片", systemImage: "photo.badge.plus")
                .foregroundStyle(.secondary)
            #endif
        } header: {
            HStack {
                Text(title)
                if !imageUrls.isEmpty { Text("\(imageUrls.count) 张") }
            }
        } footer: {
            if showsCoverLabel { Text("第一张照片会用作封面") }
        }
        .lolitaCollectionRowInsets()
        .listRowBackground(colorScheme == .dark ? skinManager.current.cardColorDark : skinManager.current.cardColor)
        #if os(iOS)
        .onDisappear {
            importTask?.cancel()
            importTask = nil
            importId = nil
            isImporting = false
            selectedPhotos = []
            onImportingChanged(false)
        }
        #endif
    }
}

struct EditSelectedItemRow: View {
    let item: Item
    var order: Int? = nil
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let order {
                Text("\(order)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            LolitaThumbnail(path: item.imageUrls.values.first, symbol: "hanger", width: 40, height: 52)
            EditItemSummary(item: item)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("移除\(item.name)")
        }
        .padding(.vertical, 3)
    }
}

struct EditItemSummary: View {
    let item: Item

    private var details: String {
        [item.colors.values.joined(separator: "、"), item.season ?? "", item.style ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
            if !details.isEmpty {
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EditItemSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var skinManager: SkinManager
    @State private var search = ""

    let title: String
    let items: [Item]
    let selectedIds: Set<Int64>
    var footer: String? = nil
    let onToggle: (Int64) -> Void

    private var filteredItems: [Item] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var accent: Color {
        colorScheme == .dark ? skinManager.current.primaryColorDark : skinManager.current.primaryColor
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        items.isEmpty ? "暂无可选服饰" : "未找到服饰",
                        systemImage: items.isEmpty ? "hanger" : "magnifyingglass",
                        description: Text(items.isEmpty ? "添加服饰后即可在这里选择" : "试试其他关键词")
                    )
                } else {
                    Section {
                        ForEach(filteredItems, id: \.id) { item in
                            Button { onToggle(item.id) } label: {
                                HStack(spacing: 12) {
                                    LolitaThumbnail(path: item.imageUrls.values.first, symbol: "hanger", width: 40, height: 52)
                                    EditItemSummary(item: item)
                                    Image(systemName: selectedIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selectedIds.contains(item.id) ? accent : .secondary)
                                }
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedIds.contains(item.id) ? .isSelected : [])
                        }
                    } header: {
                        Text("已选择 \(selectedIds.count) 件")
                    } footer: {
                        if let footer { Text(footer) }
                    }
                    .lolitaCollectionRowInsets()
                    .listRowBackground(colorScheme == .dark ? skinManager.current.cardColorDark : skinManager.current.cardColor)
                }
            }
            .searchable(text: $search, prompt: "搜索服饰名称")
            .lolitaNavBar(title: title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
