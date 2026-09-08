import SwiftUI

struct EditorView: View {
    let editing: EditingPhoto
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recipe: PhotoRecipe
    @State private var savedRecipe: PhotoRecipe
    @State private var selected: UUID?
    @State private var base: UIImage?
    @State private var undoStack: [PhotoRecipe] = []
    @State private var redoStack: [PhotoRecipe] = []
    @State private var dragStart: CGPoint?
    @State private var scaleStart: Double?
    @State private var busy = false
    @State private var message: String?
    @State private var discard = false
    @State private var shareImage: UIImage?
    @FocusState private var typing: Bool
    @State private var tab = 0
    init(editing: EditingPhoto, onSaved: @escaping () -> Void) {
        self.editing = editing; self.onSaved = onSaved
        _recipe = State(initialValue: editing.project.recipe)
        _savedRecipe = State(initialValue: editing.project.recipe)
        _selected = State(initialValue: editing.project.recipe.captions.first?.id)
    }
    private var selectedIndex: Int? { recipe.captions.firstIndex { $0.id == selected } }
    private var renderKey: String { "\(recipe.beauty)-\(recipe.brightness)-\(recipe.quarterTurns)-\(recipe.crop?.rawValue ?? "original")" }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("写真に、ひとこと。").font(.custom("Yomogi-Regular", size: 25))
                    Spacer()
                    Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(undoStack.isEmpty).accessibilityLabel("取り消す")
                    Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(redoStack.isEmpty).accessibilityLabel("やり直す")
                }.padding(.horizontal, 22).padding(.vertical, 12)
                GeometryReader { geometry in
                    if let base {
                        let fit = min(geometry.size.width / base.size.width, geometry.size.height / base.size.height)
                        let size = CGSize(width: base.size.width * fit, height: base.size.height * fit)
                        ZStack {
                            Image(uiImage: base).resizable()
                            ForEach(recipe.captions) { caption in
                                let label = ImageProcessor.shared.captionImage(caption, imageWidth: 1000)
                                Image(uiImage: label).resizable()
                                    .frame(width: label.size.width * size.width / 1000, height: label.size.height * size.width / 1000)
                                    .overlay { if selected == caption.id { RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3])) } }
                                    .rotationEffect(.degrees(caption.rotation))
                                    .position(x: caption.x * size.width, y: caption.y * size.height)
                                    .onTapGesture { selected = caption.id; tab = 0 }
                                    .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                                        guard let index = recipe.captions.firstIndex(where: { $0.id == caption.id }) else { return }
                                        if dragStart == nil { checkpoint(); dragStart = CGPoint(x: caption.x, y: caption.y); selected = caption.id; typing = false }
                                        recipe.captions[index].x = min(0.95, max(0.05, dragStart!.x + value.translation.width / size.width))
                                        recipe.captions[index].y = min(0.95, max(0.05, dragStart!.y + value.translation.height / size.height))
                                    }.onEnded { _ in dragStart = nil })
                                    .simultaneousGesture(MagnificationGesture().onChanged { value in
                                        guard let index = recipe.captions.firstIndex(where: { $0.id == caption.id }) else { return }
                                        if scaleStart == nil { checkpoint(); scaleStart = caption.size }
                                        recipe.captions[index].size = min(0.14, max(0.025, scaleStart! * value))
                                    }.onEnded { _ in scaleStart = nil })
                            }
                        }.frame(width: size.width, height: size.height).clipped()
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                }.padding(.horizontal, 16).frame(maxHeight: .infinity)
                Picker("編集ツール", selection: $tab) {
                    Text("ことば").tag(0); Text("写真・ビューティー").tag(1)
                }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.top, 14)
                ScrollView {
                    if tab == 0 { captionControls } else { photoControls }
                }.frame(height: typing ? 160 : 230)
                HStack(spacing: 12) {
                    Button { save(export: false) } label: { Label("下書き", systemImage: "tray.and.arrow.down").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                    Button { save(export: true) } label: { Label("写真に保存", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                    Button { share() } label: { Image(systemName: "square.and.arrow.up").frame(height: 28) }.buttonStyle(.bordered).accessibilityLabel("共有")
                }.padding(16)
            }
            .background(Palette.paper).foregroundStyle(Palette.ink).tint(Palette.accent)
            .navigationTitle("EDIT YOUR MEMORY").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { if recipe != savedRecipe { discard = true } else { dismiss() } } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完了") { typing = false } }
            }
            .disabled(busy)
            .overlay { if busy { ZStack { Color.black.opacity(0.2).ignoresSafeArea(); ProgressView("写真を準備しています…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) } } }
            .task(id: renderKey) {
                do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
                let current = recipe; let original = editing.image
                let rendered = await Task.detached(priority: .userInitiated) { ImageProcessor.shared.base(original, recipe: current, maxDimension: 1400) }.value
                if !Task.isCancelled { base = rendered }
            }
            .alert("PenPhoto", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
            .confirmationDialog("保存していない変更があります", isPresented: $discard, titleVisibility: .visible) {
                Button("下書きに保存して閉じる") { save(export: false, close: true) }
                Button("変更を破棄して閉じる", role: .destructive) { dismiss() }
                Button("編集を続ける", role: .cancel) {}
            }
            .sheet(isPresented: Binding(get: { shareImage != nil }, set: { if !$0 { shareImage = nil } })) { if let shareImage { ShareSheet(image: shareImage) } }
        }.interactiveDismissDisabled(recipe != savedRecipe)
    }
    private var captionControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(recipe.captions) { caption in
                            Button(caption.text.isEmpty ? "新しいことば" : String(caption.text.prefix(9))) { selected = caption.id }
                                .font(.caption).padding(8).background(selected == caption.id ? Palette.accent.opacity(0.15) : .white.opacity(0.7), in: Capsule())
                        }
                    }
                }
                Button { checkpoint(); let caption = Caption(text: "ひとこと", y: 0.7 - Double(recipe.captions.count % 4) * 0.12); recipe.captions.append(caption); selected = caption.id; typing = true } label: { Label("追加", systemImage: "plus") }
                    .disabled(recipe.captions.count >= 8)
            }
            if let index = selectedIndex {
                TextField("どこで、誰と、どんな日？", text: Binding(get: { recipe.captions[index].text }, set: { new in
                    checkpoint(); recipe.captions[index].text = String(new.prefix(200))
                }), axis: .vertical).lineLimit(1...4).font(.custom("Yomogi-Regular", size: 23)).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10)).focused($typing).accessibilityIdentifier("captionField")
                HStack(spacing: 15) {
                    ForEach(Ink.allCases, id: \.self) { ink in
                        Button { checkpoint(); recipe.captions[index].ink = ink } label: {
                            Circle().fill(Color(uiColor: ink.uiColor)).frame(width: 28, height: 28)
                                .overlay(Circle().stroke(recipe.captions[index].ink == ink ? Palette.accent : .gray.opacity(0.3), lineWidth: 3))
                        }.accessibilityLabel("文字色 \(ink.rawValue)")
                    }
                    Toggle("背景", isOn: Binding(get: { recipe.captions[index].backdrop }, set: { checkpoint(); recipe.captions[index].backdrop = $0 })).font(.caption)
                    Button(role: .destructive) { checkpoint(); recipe.captions.remove(at: index); selected = recipe.captions.first?.id } label: { Image(systemName: "trash") }.accessibilityLabel("コメントを削除")
                }
                HStack { Text("大きさ").font(.caption); Slider(value: $recipe.captions[index].size, in: 0.025...0.14, onEditingChanged: { if $0 { checkpoint() } }) }
                HStack { Text("傾き").font(.caption); Slider(value: $recipe.captions[index].rotation, in: -45...45, onEditingChanged: { if $0 { checkpoint() } }) }
            } else {
                Text("「＋ 追加」で、思い出にひとこと。\n文字はドラッグで移動、ピンチで拡大できます。")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 10)
            }
        }.padding(20)
    }
    private var photoControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("ビューティー", systemImage: "sparkles")
            Slider(value: $recipe.beauty, in: 0...1, onEditingChanged: { if $0 { checkpoint() } })
            Text("顔周辺を自然にやわらかくする試作フィルターです。顔がない写真には適用しません。").font(.caption).foregroundStyle(.secondary)
            HStack { Text("明るさ"); Slider(value: $recipe.brightness, in: -0.2...0.2, onEditingChanged: { if $0 { checkpoint() } }) }
            Picker("中央トリミング", selection: Binding(get: { recipe.crop }, set: { checkpoint(); recipe.crop = $0 })) {
                Text("元の比率").tag(nil as CropRatio?)
                ForEach(CropRatio.allCases, id: \.self) { ratio in Text(ratio.title).tag(Optional(ratio)) }
            }.pickerStyle(.segmented)
            Text("トリミングは写真の中央を基準にします。").font(.caption).foregroundStyle(.secondary)
            Button { checkpoint(); recipe.quarterTurns = (recipe.quarterTurns + 1) % 4 } label: { Label("写真を90°回転", systemImage: "rotate.right") }
        }.padding(20)
    }
    private func checkpoint() { undoStack.append(recipe); if undoStack.count > 60 { undoStack.removeFirst() }; redoStack.removeAll() }
    private func undo() { guard let previous = undoStack.popLast() else { return }; redoStack.append(recipe); recipe = previous; selected = recipe.captions.first?.id }
    private func redo() { guard let next = redoStack.popLast() else { return }; undoStack.append(recipe); recipe = next; selected = recipe.captions.first?.id }
    private func save(export: Bool, close: Bool = false) {
        typing = false; busy = true
        var project = editing.project; project.recipe = recipe
        let original = editing.image; let current = recipe
        Task {
            defer { busy = false }
            do {
                try await ProjectStore.shared.save(project, original: original)
                savedRecipe = current; onSaved()
                if export {
                    let image = await Task.detached(priority: .userInitiated) { ImageProcessor.shared.render(original, recipe: current) }.value
                    try await PhotoExporter.save(image)
                }
                if close { dismiss() } else { message = export ? "コメント入りの写真を写真アプリに保存しました。マイフォトから再編集できます。" : "マイフォトに下書きを保存しました。" }
            } catch { message = error.localizedDescription }
        }
    }
    private func share() {
        typing = false; busy = true
        let original = editing.image; let current = recipe
        Task { shareImage = await Task.detached(priority: .userInitiated) { ImageProcessor.shared.render(original, recipe: current) }.value; busy = false }
    }
}
struct ShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [image], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
