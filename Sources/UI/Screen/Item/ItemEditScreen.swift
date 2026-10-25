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
                TextField("服饰名称（必填）", text: $viewModel.name).accessibilityIdentifier("registration-name")
                TextField("描述（选填）", text: $viewModel.description, axis: .vertical)
                    .lineLimit(2...5)
                SearchableRecordPicker(title: "品牌", options: viewModel.brands.map { PickerRecord(id: $0.id, name: $0.name) }, selection: $viewModel.brandId)
                SearchableRecordPicker(title: "分类", options: viewModel.categories.map { PickerRecord(id: $0.id, name: $0.name) }, selection: $viewModel.categoryId).accessibilityIdentifier("registration-category")
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
                    Text("待付款").tag(ItemStatus.pendingPayment)
                    Text("待核对").tag(ItemStatus.pendingReview)
                }
                Picker("配套主件", selection: $viewModel.parentItemId) {
                    Text("独立物品").tag(nil as Int64?)
                    ForEach(viewModel.parentCandidates, id: \.id) { Text($0.name).tag($0.id as Int64?) }
                }
                .accessibilityIdentifier("parent-item-picker")
                if viewModel.parentItemId != nil {
                    Toggle("价格包含在主件订单中", isOn: $viewModel.includedInParentPrice)
                    if viewModel.includedInParentPrice {
                        Text("共价小物跟随主件购买状态，付款只在主件记录一次。已有独立账本的小物不能改为共价。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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
                if viewModel.status == .owned {
                    StoragePlacementPicker(rooms: viewModel.locations, nodes: viewModel.storageNodes,
                                           roomId: $viewModel.locationId, nodeId: $viewModel.storageNodeId)
                } else {
                    Text("仅已拥有物品可设置收纳位置").font(.caption).foregroundStyle(.secondary)
                    if viewModel.locationId != nil {
                        Text("历史位置：" + StorageTree.path(roomId: viewModel.locationId, nodeId: viewModel.storageNodeId, rooms: viewModel.locations, nodes: viewModel.storageNodes))
                        Button("清除历史位置") { viewModel.locationId = nil; viewModel.storageNodeId = nil }
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
                Menu("常用尺码") { ForEach(viewModel.sizeOptions, id: \.self) { value in Button(value) { viewModel.size = value } } }
                LabeledContent("尺码") {
                    TextField("如 S、M、均码", text: $viewModel.size).accessibilityIdentifier("registration-size")
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("款式信息")
            }
            .lolitaCollectionRowInsets()
            .listRowBackground(cardBackground)

            registrationSection

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
                onImportingChanged: { isImportingPhotos = $0 },
                onSetCover: viewModel.setCover
            )

            EditPhotosSection(
                title: "尺码／详情图", imageUrls: viewModel.detailImages, aspectRatio: 1,
                onAddData: { data in if !isLeaving { viewModel.addDetailImageData(data) } },
                onRemove: viewModel.removeDetailImage,
                onImportingChanged: { isImportingSizeChart = $0 }
            )
        }
        #if os(iOS)
        .contentMargins(.horizontal, 12, for: .scrollContent)
        #endif
        .safeAreaInset(edge: .bottom) {
            LolitaEditorSaveBar(title: "保存物品", enabled: canSave, identifier: "registration-save") { saveItem() }
        }
        .disabled(viewModel.isSaving)
        .onChange(of: viewModel.parentItemId) { _, id in
            if id == nil { viewModel.includedInParentPrice = false }
        }
        .scrollDismissesKeyboard(.interactively)
        .interactiveDismissDisabled(viewModel.isSaving || viewModel.hasChanges || isImportingPhotos || isImportingSizeChart)
        .confirmationDialog("保留这次编辑吗？", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("放弃更改", role: .destructive) {
                guard !viewModel.isSaving else { return }
                Task {
                    do { try await viewModel.discardDraft(); discardAndDismiss() }
                    catch { saveError = userFacingError(error) }
                }
            }
            .disabled(viewModel.isSaving)
            Button("保存草稿并退出") {
                Task {
                    do { try await viewModel.persistDraft(); isLeaving = true; dismiss() }
                    catch { saveError = userFacingError(error) }
                }
            }
            Button("继续编辑", role: .cancel) {}
        }
        .task(id: viewModel.draftState) {
            do { try await Task.sleep(for: .milliseconds(350)); try Task.checkCancellation(); if !isLeaving { await viewModel.autosaveDraft() } }
            catch { }
        }
        .alert("发现未完成的物品草稿", isPresented: Binding(get: { viewModel.pendingDraft != nil }, set: { _ in })) {
            Button("继续草稿") { do { try viewModel.resumeDraft() } catch { saveError = userFacingError(error) } }
            Button("删除草稿", role: .destructive) { Task { do { try await viewModel.rejectPendingDraft() } catch { saveError = userFacingError(error) } } }
        } message: { Text("可恢复上次的文字和图片；保存前请核对物品及收纳位置。") }
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
            else { Task { do { try await viewModel.discardDraft(); discardAndDismiss() } catch { saveError = userFacingError(error) } } }
        })
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("收起键盘") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                    .accessibilityIdentifier("dismiss-registration-keyboard")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存", action: saveItem).disabled(!canSave)
            }
        }
        #endif
        .task { await viewModel.load(itemId: itemId, defaultStatus: defaultStatus) }
    }

    private var canSave: Bool { !viewModel.name.trimmingCharacters(in: .whitespaces).isEmpty && !viewModel.isSaving && !isImportingPhotos && !isImportingSizeChart }
    private func saveItem() {
        guard canSave else { return }
        Task { do { try await viewModel.save(); isLeaving = true; dismiss() } catch { saveError = userFacingError(error) } }
    }
    private var registrationSection: some View {
        Section("物品规格") {
            LabeledContent("稳定品类", value: viewModel.semantic.label)
            Picker("组合", selection: $viewModel.composition) {
                ForEach(ItemComposition.allCases, id: \.self) { Text($0.label).tag($0) }
            }.accessibilityIdentifier("item-composition")
            TextField("图案／纹样", text: $viewModel.specifications.pattern)
            ForEach(WardrobeSpecifications.fields[viewModel.semantic.profile] ?? [], id: \.0) { field in
                TextField(field.1, text: Binding(get: { viewModel.specifications.profiles[viewModel.semantic.profile]?[field.0] ?? "" },
                                                set: { viewModel.specifications.profiles[viewModel.semantic.profile, default: [:]][field.0] = $0 }))
                    .accessibilityIdentifier("spec-" + field.0)
            }
            if viewModel.semantic == .unconfirmed { Text("请在分类管理中确认稳定品类，再填写专属规格。改分类名称不会改变类型。").font(.caption).foregroundStyle(.secondary) }
            if let message = viewModel.draftMessage { Text(message).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("draft-status") }
        }
        .lolitaCollectionRowInsets()
        .listRowBackground(cardBackground)
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
    @ScaledMetric(relativeTo: .subheadline) private var colorMinimumWidth: CGFloat = 92
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: colorMinimumWidth))], spacing: 10) {
            ForEach(visibleColors, id: \.self) { color in
                let selected = selectedColors.contains(color)
                Button {
                    if selected { selectedColors.remove(color) }
                    else { selectedColors.insert(color) }
                } label: {
                    HStack(spacing: 4) {
                        if selected { SkinIcon(systemName: "checkmark", size: 12) }
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
                SkinLabel("自定义", systemImage: "plus")
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
                SkinIcon(systemName: "chevron.right", size: 12)
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
                                        SkinIcon(systemName: "checkmark", size: 17)
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
    var identifierPrefix = ""
    let onRemove: (Int) -> Void
    var onSetCover: ((Int) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: skinManager.current.spacingM) {
                ForEach(Array(imageUrls.enumerated()), id: \.offset) { index, path in
                    VStack(spacing: 4) {
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
                                    SkinIcon(systemName: "xmark", size: 12)
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(.black.opacity(0.6), in: Circle())
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("移除第 \(index + 1) 张照片")
                                .accessibilityIdentifier("photo-remove-\(identifierPrefix)-\(index)")
                            }
                    }
                    if let onSetCover, index > 0 {
                        Button("设为封面") { onSetCover(index) }.font(.caption).buttonStyle(.bordered)
                            .accessibilityIdentifier("set-cover-\(index)")
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
    var onSetCover: ((Int) -> Void)? = nil

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
                    aspectRatio: aspectRatio, identifierPrefix: title,
                    onRemove: onRemove, onSetCover: onSetCover
                )
            }
            #if os(iOS)
            let showsPhotoImportProgress = isImporting
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 10, matching: .images) {
                HStack {
                    SkinLabel("添加照片", systemImage: "photo.badge.plus")
                    Spacer()
                    if showsPhotoImportProgress { ProgressView() }
                }
            }
            .disabled(isImporting)
            .accessibilityIdentifier("add-photos-" + title)
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
            SkinLabel("macOS 暂不支持添加照片", systemImage: "photo.badge.plus")
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
                SkinIcon(systemName: "xmark.circle.fill", size: 17)
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
                                    SkinIcon(systemName: selectedIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
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
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("完成选择（\(selectedIds.count) 件）") { dismiss() }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("item-selection-done")
                }.padding(12).frame(maxWidth: .infinity).background(.regularMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
