import SwiftUI
import PhotosUI

@main
struct PenPhotoApp: App {
    var body: some Scene { WindowGroup { HomeView().preferredColorScheme(.light) } }
}

struct HomeView: View {
    @StateObject private var camera = CameraService()
    @Environment(\.scenePhase) private var scenePhase
    @State private var editing: EditingPhoto?
    @State private var picker: PhotosPickerItem?
    @State private var library = false
    @AppStorage("captureAspect") private var captureAspect: CaptureAspect = .standard
    @State private var pendingCaptureRecipe: PhotoRecipe?
    @State private var beauty = false
    @State private var strength = 0.45
    @State private var grid = false
    @State private var flash = false
    @State private var timer = false
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var exposure = 0.0
    @State private var loading = false
    @State private var importError: String?
    @State private var showSettings = false
    var body: some View {
        GeometryReader { geometry in
        Group {
        if captureAspect == .wide {
            wideCamera(safeArea: geometry.safeAreaInsets)
        } else {
        let previewSize = captureAspect.previewSize(in: CGSize(width: geometry.size.width - 32, height: max(170, geometry.size.height - 305)))
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) { Image(systemName: "pencil.tip.crop.circle").font(.title2); Text("PenPhoto").font(.system(size: 29, weight: .semibold, design: .serif)) }
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "gearshape").font(.title3) }.accessibilityLabel("設定とアプリ情報")
            }.padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 6)
            HStack { Text("今日を撮って、ことばを添えて。").font(.custom("Yomogi-Regular", size: 18)); Spacer(); Text("PHOTO DIARY").font(.system(size: 9, weight: .semibold)).tracking(1.8) }.padding(.horizontal, 24).padding(.bottom, 20)
            ZStack {
                Color(red: 0.12, green: 0.17, blue: 0.15)
                CameraPreview(camera: camera)
                if beauty, let preview = camera.beautyPreview { GeometryReader { geo in Image(uiImage: preview).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped() }.allowsHitTesting(false) }
                if grid {
                    GeometryReader { geo in
                        Path { path in
                            for n in 1...2 {
                                let x = geo.size.width * CGFloat(n) / 3; let y = geo.size.height * CGFloat(n) / 3
                                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geo.size.height))
                                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geo.size.width, y: y))
                            }
                        }.stroke(.white.opacity(0.35), lineWidth: 0.5)
                    }.allowsHitTesting(false)
                }
                if !camera.ready {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.macro").font(.system(size: 44, weight: .ultraLight))
                        Text("何気ない今日も、\n残したい思い出に。").font(.custom("Yomogi-Regular", size: 27)).multilineTextAlignment(.center)
                        Text(camera.error ?? "カメラを準備しています…").font(.caption).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.65)).padding(.horizontal, 32)
                        Button("サンプルで編集を試す") { openSample() }.font(.subheadline.bold()).padding(.horizontal, 20).padding(.vertical, 12).background(.white.opacity(0.12), in: Capsule())
                        if camera.error != nil {
                            HStack(spacing: 20) {
                                Button("再開") { camera.start() }
                                Button("設定を開く") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                            }.font(.caption)
                        }
                    }.foregroundStyle(.white)
                }
                VStack {
                    HStack {
                        tool(flash ? "bolt.fill" : "bolt.slash", label: "フラッシュ", active: flash) { flash.toggle() }.disabled(!camera.hasFlash)
                        Spacer()
                        Button { captureAspect = captureAspect == .standard ? .wide : .standard } label: {
                            Text(captureAspect.title).font(.system(size: 13, weight: .semibold, design: .rounded))
                                .frame(width: 54, height: 36).background(.black.opacity(0.35), in: Capsule())
                        }.accessibilityLabel("撮影比率").accessibilityValue(captureAspect.title).accessibilityIdentifier("captureAspect")
                            .disabled(camera.capturing || countdown != nil)
                        Spacer()
                        tool("timer", label: "3秒タイマー", active: timer) { timer.toggle() }
                        tool("grid", label: "グリッド", active: grid) { grid.toggle() }
                    }
                    Spacer()
                    if camera.ready {
                        HStack(spacing: 10) {
                            Image(systemName: "minus.magnifyingglass")
                            Slider(value: $camera.zoom, in: 1...max(1.01, camera.maxZoom)).onChange(of: camera.zoom) { _, value in camera.setZoom(value) }
                            Text(String(format: "%.1f×", camera.zoom)).font(.caption.monospacedDigit()).frame(width: 40)
                        }.padding(10).background(.black.opacity(0.35), in: Capsule()).padding(.horizontal, 40)
                    }
                }.padding(16).foregroundStyle(.white)
                if let countdown { Text("\(countdown)").font(.system(size: 88, weight: .thin)).foregroundStyle(.white).shadow(radius: 10) }
            }.frame(width: previewSize.width, height: previewSize.height).clipShape(RoundedRectangle(cornerRadius: 24)).frame(maxWidth: .infinity)
            HStack(spacing: 24) {
                Button { beauty = false } label: { Text("通常").fontWeight(beauty ? .regular : .bold).foregroundStyle(beauty ? .secondary : Palette.accent) }
                Button { beauty = true } label: { Label("ビューティー", systemImage: "sparkles").fontWeight(beauty ? .bold : .regular).foregroundStyle(beauty ? Palette.accent : .secondary) }
            }.font(.subheadline).padding(.top, 18)
            HStack(spacing: 10) {
                Image(systemName: beauty ? "sparkles" : "sun.max").font(.caption)
                if beauty { Slider(value: $strength, in: 0...1); Text("\(Int(strength * 100))%").font(.caption.monospacedDigit()).frame(width: 36) }
                else { Slider(value: $exposure, in: -2...2).onChange(of: exposure) { _, value in camera.setExposure(Float(value)) }; Text("露出").font(.caption) }
            }.padding(.horizontal, 48).padding(.top, 6)
            Spacer(minLength: 8)
            HStack {
                PhotosPicker(selection: $picker, matching: .images) { VStack(spacing: 5) { Image(systemName: "photo.on.rectangle").font(.title2); Text("読み込む").font(.caption2) }.frame(width: 70) }.accessibilityIdentifier("importPhoto")
                Spacer()
                Button { shutter() } label: { ZStack { Circle().stroke(Palette.accent, lineWidth: 2).frame(width: 78, height: 78); Circle().fill(Palette.accent).frame(width: 64, height: 64); if camera.capturing { ProgressView().tint(.white) } else { Image(systemName: "camera").font(.title2).foregroundStyle(.white) } } }
                    .disabled(!camera.ready || camera.capturing || countdown != nil).accessibilityLabel("写真を撮る")
                Spacer()
                Button { camera.switchCamera(); exposure = 0 } label: { VStack(spacing: 5) { Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title2); Text("切り替え").font(.caption2) }.frame(width: 70) }.disabled(!camera.ready || camera.capturing || countdown != nil)
            }.padding(.horizontal, 30)
            Button { library = true } label: { HStack { Image(systemName: "square.stack"); Text("マイフォト"); Image(systemName: "chevron.right").font(.caption2) }.font(.caption).padding(.vertical, 14) }
        }
        .background(Palette.paper.ignoresSafeArea()).foregroundStyle(Palette.ink).tint(Palette.accent)
        }
        }
        .statusBarHidden(captureAspect == .wide)
        .task { UIDevice.current.beginGeneratingDeviceOrientationNotifications(); if ProcessInfo.processInfo.arguments.contains("--sample-editor") { openSample() } else { camera.start() } }
        .onChange(of: beauty) { _, _ in camera.setBeauty(beauty ? strength : 0) }
        .onChange(of: strength) { _, value in camera.setBeauty(beauty ? value : 0) }
        .onChange(of: camera.captured) { _, image in
            guard let image else { return }
            editing = EditingPhoto(project: PhotoProject(recipe: pendingCaptureRecipe ?? PhotoRecipe(beauty: beauty ? strength : 0, captureAspect: captureAspect)), image: image)
            pendingCaptureRecipe = nil
            camera.captured = nil
        }
        .onChange(of: editing?.id) { _, id in if id != nil { cancelCountdown(); camera.stop() } else if !library && scenePhase == .active { camera.start() } }
        .onChange(of: library) { _, shown in if shown { cancelCountdown(); camera.stop() } else if editing == nil && scenePhase == .active { camera.start() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active && editing == nil && !library { camera.start() } else { cancelCountdown(); camera.stop() } }
        .onChange(of: picker) { _, item in
            guard let item else { return }; loading = true
            Task {
                defer { loading = false; picker = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw AppError.message("この写真を読み込めませんでした。別の写真を選んでください。") }
                    editing = EditingPhoto(project: PhotoProject(), image: image)
                } catch { importError = error.localizedDescription }
            }
        }
        .fullScreenCover(item: $editing) { photo in EditorView(editing: photo, onSaved: {}) }
        .sheet(isPresented: $library) { LibraryView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .overlay { if loading { ProgressView("写真を読み込み中…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .alert("読み込みできませんでした", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) { Button("OK") { importError = nil } } message: { Text(importError ?? "") }
    }
    }
    /// Full-width 9:16 viewfinder with controls overlaid. The small remaining screen
    /// area belongs to the black control bars, so display and saved framing still agree.
    private func wideCamera(safeArea: EdgeInsets) -> some View {
        GeometryReader { screen in
            let viewfinderHeight = min(screen.size.height, screen.size.width * 16 / 9)
            ZStack {
                Color.black
                ZStack {
                    Color(red: 0.12, green: 0.17, blue: 0.15)
                    CameraPreview(camera: camera)
                    if beauty, let preview = camera.beautyPreview {
                        Image(uiImage: preview).resizable().scaledToFill()
                            .frame(width: screen.size.width, height: viewfinderHeight).clipped().allowsHitTesting(false)
                    }
                    if grid {
                        Path { path in
                            for n in 1...2 {
                                let x = screen.size.width * CGFloat(n) / 3
                                let y = viewfinderHeight * CGFloat(n) / 3
                                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: viewfinderHeight))
                                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: screen.size.width, y: y))
                            }
                        }.stroke(.white.opacity(0.4), lineWidth: 0.5).allowsHitTesting(false)
                    }
                    if !camera.ready {
                        VStack(spacing: 14) {
                            Image(systemName: "camera").font(.system(size: 38, weight: .light))
                            Text(camera.error ?? "カメラを準備しています…")
                                .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.75))
                            Button("サンプルで編集を試す") { openSample() }
                                .padding(.horizontal, 18).padding(.vertical, 12).background(.white.opacity(0.15), in: Capsule())
                            if camera.error != nil {
                                HStack(spacing: 24) {
                                    Button("再開") { camera.start() }
                                    Button("設定を開く") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                                }.font(.caption)
                            }
                        }.padding(.horizontal, 40)
                    }
                    if let countdown { Text("\(countdown)").font(.system(size: 88, weight: .thin)).shadow(radius: 10) }
                }
                .frame(width: screen.size.width, height: viewfinderHeight).clipped()
                .accessibilityIdentifier("wideViewfinder")

                VStack(spacing: 0) {
                    HStack {
                        tool(flash ? "bolt.fill" : "bolt.slash", label: "フラッシュ", active: flash) { flash.toggle() }.disabled(!camera.hasFlash)
                        Spacer()
                        Button { captureAspect = .standard } label: {
                            Text("16:9").font(.system(size: 14, weight: .semibold)).frame(width: 58, height: 44)
                        }.accessibilityLabel("撮影比率").accessibilityValue("16:9").accessibilityIdentifier("captureAspect")
                            .disabled(camera.capturing || countdown != nil)
                        Spacer()
                        tool("timer", label: "3秒タイマー", active: timer) { timer.toggle() }
                        tool("grid", label: "グリッド", active: grid) { grid.toggle() }
                        Button { showSettings = true } label: { Image(systemName: "gearshape").frame(width: 44, height: 44) }.accessibilityLabel("設定とアプリ情報")
                    }.padding(.horizontal, 16).padding(.top, max(12, safeArea.top)).padding(.bottom, 12)
                        .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
                    Spacer(minLength: 0)
                    VStack(spacing: 12) {
                        if camera.ready {
                            HStack(spacing: 12) {
                                Image(systemName: "minus.magnifyingglass")
                                Slider(value: $camera.zoom, in: 1...max(1.01, camera.maxZoom))
                                    .onChange(of: camera.zoom) { _, value in camera.setZoom(value) }
                                Text(String(format: "%.1f×", camera.zoom)).font(.caption.monospacedDigit()).frame(width: 40)
                            }.padding(.horizontal, 16).padding(.vertical, 6)
                                .background(.black.opacity(0.4), in: Capsule()).padding(.horizontal, 64)
                        }
                        HStack(spacing: 30) {
                            Button { beauty = false } label: { Text("写真").foregroundStyle(beauty ? .white : .yellow) }
                            Button { beauty = true } label: { Text("ビューティー").foregroundStyle(beauty ? .yellow : .white) }
                        }.font(.system(size: 14, weight: .semibold))
                        HStack(spacing: 12) {
                            Image(systemName: beauty ? "sparkles" : "sun.max")
                            if beauty {
                                Slider(value: $strength, in: 0...1)
                                Text("\(Int(strength * 100))%").font(.caption.monospacedDigit()).frame(width: 36)
                            } else {
                                Slider(value: $exposure, in: -2...2).onChange(of: exposure) { _, value in camera.setExposure(Float(value)) }
                                Text("露出").font(.caption)
                            }
                        }.padding(.horizontal, 52)
                        HStack {
                            PhotosPicker(selection: $picker, matching: .images) {
                                Image(systemName: "photo.on.rectangle").font(.title2).frame(width: 60, height: 60)
                                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            }.accessibilityLabel("読み込む").accessibilityIdentifier("importPhoto")
                            Spacer()
                            Button { shutter() } label: {
                                ZStack {
                                    Circle().stroke(.white, lineWidth: 3).frame(width: 80, height: 80)
                                    Circle().fill(.white).frame(width: 68, height: 68)
                                    if camera.capturing { ProgressView().tint(.black) }
                                }
                            }.disabled(!camera.ready || camera.capturing || countdown != nil).accessibilityLabel("写真を撮る")
                            Spacer()
                            Button { camera.switchCamera(); exposure = 0 } label: {
                                Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title2).frame(width: 60, height: 60).background(.white.opacity(0.12), in: Circle())
                            }.disabled(!camera.ready || camera.capturing || countdown != nil).accessibilityLabel("切り替え")
                        }.padding(.horizontal, 32)
                        Button { library = true } label: { Label("マイフォト", systemImage: "square.stack").font(.caption).frame(height: 30) }
                    }
                    .padding(.top, 22).padding(.bottom, max(12, safeArea.bottom))
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.7), .black.opacity(0.95)], startPoint: .top, endPoint: .bottom))
                }
            }.foregroundStyle(.white).tint(.yellow)
        }.ignoresSafeArea()
    }

    private func tool(_ icon: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 36, height: 36).foregroundStyle(active ? .yellow : .white).background(.black.opacity(0.25), in: Circle()) }.accessibilityLabel(label).accessibilityValue(active ? "オン" : "オフ")
    }
    private func shutter() {
        pendingCaptureRecipe = PhotoRecipe(beauty: beauty ? strength : 0, captureAspect: captureAspect)
        guard timer else { camera.capture(flash: flash); return }
        countdownTask = Task {
            for value in (1...3).reversed() {
                countdown = value
                do { try await Task.sleep(for: .seconds(1)) } catch { countdown = nil; return }
            }
            countdown = nil
            guard !Task.isCancelled else { return }; camera.capture(flash: flash)
        }
    }
    private func cancelCountdown() { countdownTask?.cancel(); countdownTask = nil; countdown = nil }
    private func openSample() {
        editing = EditingPhoto(project: PhotoProject(recipe: PhotoRecipe(captions: [Caption(text: "寄り道した、午後のカフェ。") ], captureAspect: captureAspect)), image: SamplePhoto.make())
    }
}

struct LibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var projects: [PhotoProject] = []
    @State private var editing: EditingPhoto?
    @State private var message: String?
    @State private var revision = 0
    var body: some View {
        NavigationStack {
            ScrollView {
                if projects.isEmpty {
                    ContentUnavailableView("まだ、まっさらなアルバム。", systemImage: "photo.on.rectangle.angled", description: Text("写真にことばを添えて保存すると、\nここからいつでも再編集できます。")) .padding(.top, 80)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(projects) { project in
                        Button {
                            Task { do { editing = try await ProjectStore.shared.load(project) } catch { message = error.localizedDescription } }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ProjectThumbnail(id: project.id, revision: revision).aspectRatio(3 / 4, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
                                Text(project.title).font(.custom("Yomogi-Regular", size: 17)).lineLimit(2)
                                Text(project.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                            }.foregroundStyle(Palette.ink)
                        }
                    }
                }.padding(20)
            }.background(Palette.paper).navigationTitle("マイフォト")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } } }
                .task(id: revision) { do { projects = try await ProjectStore.shared.list() } catch { message = error.localizedDescription } }
                .fullScreenCover(item: $editing) { photo in EditorView(editing: photo) { revision += 1 } }
                .alert("写真を読み込めませんでした", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
        }.tint(Palette.accent)
    }
}
struct ProjectThumbnail: View {
    let id: UUID
    let revision: Int
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geo in
            if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped() }
            else { Palette.ink.opacity(0.08).overlay { ProgressView() } }
        }.task(id: revision) { image = await ProjectStore.shared.thumbnail(id) }
    }
}
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("PenPhotoについて") { Text("写真に、手書き風のひとことを残すカメラ。\n最初の開発版です。"); Text("写真と編集内容はこのiPhone内に保存されます。外部サーバーへの送信は行いません。"); Text("アプリを削除するとマイフォトも削除されます。残したい写真は「写真に保存」してください。") }
                Section("ビューティー") { Text("顔周辺の平滑化を行う試作です。肌の領域を完全には分離できないため、髪や背景の一部がやわらかくなる場合があります。") }
                Section("フォント") { Text("Yomogi — SIL Open Font License 1.1"); NavigationLink("フォントライセンス") { ScrollView { Text((try? String(contentsOf: Bundle.main.url(forResource: "OFL-Yomogi", withExtension: "txt")!, encoding: .utf8)) ?? "").font(.caption).padding() }.navigationTitle("ライセンス") } }
            }.navigationTitle("設定とアプリ情報").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } } }
        }.tint(Palette.accent)
    }
}

enum SamplePhoto {
    static func make() -> UIImage {
        let size = CGSize(width: 1200, height: 1600)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let cg = renderer.cgContext
            UIColor(red: 0.77, green: 0.78, blue: 0.65, alpha: 1).setFill(); cg.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.32, green: 0.44, blue: 0.36, alpha: 1).setFill(); cg.fill(CGRect(x: 0, y: 0, width: 1200, height: 700))
            UIColor(red: 0.89, green: 0.8, blue: 0.65, alpha: 1).setFill()
            let table = UIBezierPath(); table.move(to: CGPoint(x: 0, y: 720)); table.addLine(to: CGPoint(x: 1200, y: 580)); table.addLine(to: CGPoint(x: 1200, y: 1600)); table.addLine(to: CGPoint(x: 0, y: 1600)); table.close(); table.fill()
            cg.setShadow(offset: CGSize(width: 15, height: 25), blur: 30, color: UIColor.black.withAlphaComponent(0.18).cgColor)
            UIColor(red: 0.96, green: 0.94, blue: 0.88, alpha: 1).setFill(); cg.fillEllipse(in: CGRect(x: 250, y: 610, width: 700, height: 570))
            UIColor.white.setFill(); cg.fillEllipse(in: CGRect(x: 725, y: 710, width: 180, height: 180))
            UIColor(red: 0.88, green: 0.86, blue: 0.78, alpha: 1).setFill(); cg.fillEllipse(in: CGRect(x: 350, y: 640, width: 440, height: 420))
            cg.setShadow(offset: .zero, blur: 0)
            UIColor(red: 0.31, green: 0.19, blue: 0.12, alpha: 1).setFill(); cg.fillEllipse(in: CGRect(x: 380, y: 670, width: 380, height: 355))
            UIColor(red: 0.81, green: 0.65, blue: 0.45, alpha: 1).setFill(); cg.fillEllipse(in: CGRect(x: 445, y: 730, width: 250, height: 230))
            let title = "SLOW AFTERNOON" as NSString
            title.draw(at: CGPoint(x: 105, y: 180), withAttributes: [.font: UIFont.systemFont(ofSize: 32, weight: .light), .foregroundColor: UIColor.white.withAlphaComponent(0.8), .kern: 8])
            let note = "PenPhoto / 編集用サンプル" as NSString
            note.draw(at: CGPoint(x: 100, y: 1470), withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.darkGray])
        }
    }
}
