import SwiftUI
#if os(iOS)
import PhotosUI
import AVFoundation
#endif

struct CalendarBackground: View {
    var overlayOpacity: Double = 0.76
    @AppStorage("paymentCalendarBackgroundPath") private var path = ""
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if !path.isEmpty {
            GeometryReader { geometry in
                LolitaShimmerImage(url: ImageFileHelper.fileURL(for: path))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .overlay((colorScheme == .dark ? skinManager.current.backgroundColorDark : skinManager.current.backgroundColor).opacity(overlayOpacity))
                    .clipped()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

struct CalendarBackgroundPicker: View {
    @Binding var showActions: Bool

    init(showActions: Binding<Bool> = .constant(false)) { _showActions = showActions }
    @AppStorage("paymentCalendarBackgroundPath") private var path = ""
    @State private var error: String?
    @State private var showPreview = false
    #if os(iOS)
    @State private var selection: PhotosPickerItem?
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var importTask: Task<Void, Never>?
    @State private var requestId: UUID?
    #endif

    var body: some View {
        Menu {
            actions
        } label: { SkinIcon(systemName: "photo.on.rectangle.angled") }
        .accessibilityLabel("设置日历背景")
        .confirmationDialog("日历背景", isPresented: $showActions, titleVisibility: .visible) { actions }
        .alert("日历背景", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("确定") { error = nil }
        } message: { Text(error ?? "") }
        #if os(iOS)
        .photosPicker(isPresented: $showPhotos, selection: $selection, matching: .images)
        .sheet(isPresented: $showCamera) {
            CalendarCameraCapture { image in
                if let image {
                    if let stored = ImageFileHelper.save(image: image) { replaceBackground(with: stored) }
                    else { error = "无法保存照片，请重试。" }
                }
                showCamera = false
            }.ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showPreview) { FullScreenImageViewer(url: ImageFileHelper.fileURL(for: path)) }
        .onChange(of: selection) { _, selection in
            importTask?.cancel()
            guard let selection else { return }
            let id = UUID()
            requestId = id
            importTask = Task {
                defer { if requestId == id { self.selection = nil; requestId = nil; importTask = nil } }
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self), !Task.isCancelled,
                          requestId == id, let image = UIImage(data: data),
                          let stored = ImageFileHelper.save(image: image) else {
                        if !Task.isCancelled { error = "无法读取照片，请重新选择。" }
                        return
                    }
                    replaceBackground(with: stored)
                } catch { if !Task.isCancelled { self.error = userFacingError(error) } }
            }
        }
        .onDisappear { importTask?.cancel(); importTask = nil; requestId = nil; selection = nil }
        #else
        .sheet(isPresented: $showPreview) { FullScreenImageViewer(url: ImageFileHelper.fileURL(for: path)) }
        #endif
    }

    @ViewBuilder private var actions: some View {
        #if os(iOS)
        SkinButton("从相册选择", systemImage: "photo") { showPhotos = true }
        SkinButton("拍摄背景", systemImage: "camera") {
            Task {
                guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                    error = "当前设备没有可用相机，请从相册选择。"
                    return
                }
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                var allowed = status == .authorized
                if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
                if allowed { showCamera = true }
                else { error = "相机权限未开启，请在系统设置中允许访问相机。" }
            }
        }
        #endif
        if !path.isEmpty {
            SkinButton("查看背景", systemImage: "arrow.up.left.and.arrow.down.right") { showPreview = true }
            SkinButton("恢复默认", systemImage: "arrow.counterclockwise", role: .destructive) { replaceBackground(with: "") }
        }
    }

    private func replaceBackground(with newPath: String) {
        let old = path
        path = newPath
        if !old.isEmpty, old != newPath {
            try? ImageFileHelper.deleteUnreferenced(paths: [old], db: AppModule.shared.db.dbQueue)
        }
    }
}

#if os(iOS)
private struct CalendarCameraCapture: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion(info[.originalImage] as? UIImage)
        }
    }
}
#endif
