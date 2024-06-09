import Combine
import SwiftUI
import CompactSlider

/// 跟踪 StableDiffusion Pipeline 的准备状态。这包括从互联网下载、解压下载的 zip 文件、加载到内存、准备使用或错误状态。
enum PipelineState {
    case downloading(Double)
    case uncompressing
    case loading
    case ready
    case failed(Error)
}

/// 模拟本机外观，但标签是可点击的。如果观察到任何 UI 问题，将移除（添加手势到所有标签）。
struct LabelToggleDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack {
            HStack {
                Button {
                    withAnimation {
                        configuration.isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .frame(width: 12, height: 12)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .fontWeight(.bold)
                configuration.label.onTapGesture {
                    withAnimation {
                        configuration.isExpanded.toggle()
                    }
                }
                Spacer()
            }
            if configuration.isExpanded {
                configuration.content
            }
        }
        .padding()
        .background(Color.blue)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 3)
    }
}

struct ControlsView: View {
    @EnvironmentObject var generation: GenerationContext

    static let models = ModelInfo.MODELS
    
    @State private var model = Settings.shared.currentModel.modelVersion
    @State private var disclosedModel = true
    @State private var disclosedPrompt = true
    @State private var disclosedGuidance = false
    @State private var disclosedSteps = false
    @State private var disclosedPreview = false
    @State private var disclosedSeed = false
    @State private var disclosedAdvanced = false

    // TODO: 重构下载代码，与 Loading.swift（iOS）中的类似代码
    @State private var stateSubscriber: Cancellable?
    @State private var pipelineState: PipelineState = .downloading(0)
    @State private var pipelineLoader: PipelineLoader? = nil

    // TODO: 使其计算和可观察，并易于阅读
    @State private var mustShowSafetyCheckerDisclaimer = false
    @State private var mustShowModelDownloadDisclaimer = false      // 更改高级设置时

    @State private var showModelsHelp = false
    @State private var showPromptsHelp = false
    @State private var showGuidanceHelp = false
    @State private var showStepsHelp = false
    @State private var showPreviewHelp = false
    @State private var showSeedHelp = false
    @State private var showAdvancedHelp = false
    @State private var positiveTokenCount: Int = 0
    @State private var negativeTokenCount: Int = 0

    let maxSeed: UInt32 = UInt32.max
    private var textFieldLabelSeed: String { generation.seed < 1 ? "随机种子" : "种子" }
    
    var modelFilename: String? {
        guard let pipelineLoader = pipelineLoader else { return nil }
        let selectedURL = pipelineLoader.compiledURL
        guard FileManager.default.fileExists(atPath: selectedURL.path) else { return nil }
        return selectedURL.path
    }
    
    fileprivate func updateSafetyCheckerState() {
        mustShowSafetyCheckerDisclaimer = generation.disableSafety && !Settings.shared.safetyCheckerDisclaimerShown
    }
    
    fileprivate func updateComputeUnitsState() {
        Settings.shared.userSelectedComputeUnits = generation.computeUnits
        modelDidChange(model: Settings.shared.currentModel)
    }
    
    fileprivate func resetComputeUnitsState() {
        generation.computeUnits = Settings.shared.userSelectedComputeUnits ?? ModelInfo.defaultComputeUnits
    }

    fileprivate func modelDidChange(model: ModelInfo) {
        guard pipelineLoader?.model != model || pipelineLoader?.computeUnits != generation.computeUnits else {
            print("重用相同模型 \(model)，使用单位 \(generation.computeUnits)")
            return
        }

        Settings.shared.currentModel = model

        pipelineLoader?.cancel()
        pipelineState = .downloading(0)
        Task.init {
            let loader = PipelineLoader(model: model, computeUnits: generation.computeUnits, maxSeed: maxSeed)
            self.pipelineLoader = loader
            stateSubscriber = loader.statePublisher.sink { state in
                DispatchQueue.main.async {
                    switch state {
                    case .downloading(let progress):
                        pipelineState = .downloading(progress)
                    case .uncompressing:
                        pipelineState = .uncompressing
                    case .readyOnDisk:
                        pipelineState = .loading
                    case .failed(let error):
                        pipelineState = .failed(error)
                    default:
                        break
                    }
                }
            }
            do {
                generation.pipeline = try await loader.prepare()
                pipelineState = .ready
            } catch {
                print("无法加载模型，错误：\(error)")
                pipelineState = .failed(error)
            }
        }
    }
    
    fileprivate func isModelDownloaded(_ model: ModelInfo, computeUnits: ComputeUnits? = nil) -> Bool {
        PipelineLoader(model: model, computeUnits: computeUnits ?? generation.computeUnits).ready
    }
    
    fileprivate func modelLabel(_ model: ModelInfo) -> Text {
        let downloaded = isModelDownloaded(model)
        let prefix = downloaded ? "● " : "◌ "
        return Text(prefix).foregroundColor(downloaded ? .green : .secondary) + Text(model.modelVersion)
    }
    
    fileprivate func prompts() -> some View {
        VStack {
            Spacer()
            PromptTextField(text: $generation.positivePrompt, isPositivePrompt: true, model: $model)
                .frame(height: 100) // Adjusted height for larger input field
                .padding()
                .background(Color.pink.opacity(0.8))
                .cornerRadius(10)
                .padding(.top, 5)
                .frame(maxWidth: .infinity) // Ensure it fills the width of the container
            Spacer()
            PromptTextField(text: $generation.negativePrompt, isPositivePrompt: false, model: $model)
                .frame(height: 100) // Adjusted height for larger input field
                .padding()
                .background(Color.purple.opacity(0.8))
                .cornerRadius(10)
                .padding(.bottom, 5)
                .frame(maxWidth: .infinity) // Ensure it fills the width of the container
            Spacer()
        }
        .padding([.leading, .trailing], 10) // Add padding to the sides
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            
            Label("通用选项", systemImage: "gearshape.2")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Divider()
                .background(Color.white)
            
            ScrollView {
                Group {
                    DisclosureGroup(isExpanded: $disclosedModel) {
                        let revealOption = "-- reveal --"
                        Picker("", selection: $model) {
                            ForEach(Self.models, id: \.modelVersion) {
                                modelLabel($0)
                            }
                            Text("在 Finder 中显示…").tag(revealOption)
                        }
                        .onChange(of: model) { selection in
                            guard selection != revealOption else {
                                NSWorkspace.shared.selectFile(modelFilename, inFileViewerRootedAtPath: PipelineLoader.models.path)
                                model = Settings.shared.currentModel.modelVersion
                                return
                            }
                            guard let model = ModelInfo.from(modelVersion: selection) else { return }
                            modelDidChange(model: model)
                        }
                    } label: {
                        HStack {
                            Label("集市上的模型", systemImage: "cpu").foregroundColor(.secondary)
                            Spacer()
                            if disclosedModel {
                                Button {
                                    showModelsHelp.toggle()
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.plain)
                                .sheet(isPresented: $showModelsHelp) {
                                    modelsHelp($showModelsHelp)
                                }
                            }
                        }
                        .foregroundColor(.secondary)
                    }
                    Divider()
                        .background(Color.white)
                    
                    DisclosureGroup(isExpanded: $disclosedPrompt) {
                        Group {
                            prompts()
                        }
                    } label: {
                        HStack {
                            Label("文生图提示语句", systemImage: "text.quote").foregroundColor(.secondary)
                            Spacer()
                            if disclosedPrompt {
                                Button {
                                    showPromptsHelp.toggle()
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showPromptsHelp, arrowEdge: .trailing) {
                                    promptsHelp($showPromptsHelp)
                                }
                            }
                        }
                        .foregroundColor(.secondary)
                    }
                    Divider()
                        .background(Color.white)

                    let guidanceScaleValue = generation.guidanceScale.formatted("%.1f")
                    DisclosureGroup(isExpanded: $disclosedGuidance) {
                        CompactSlider(value: $generation.guidanceScale, in: 0...20, step: 0.5) {
                            Text("指导尺度")
                            Spacer()
                            Text(guidanceScaleValue)
                        }.padding(.leading, 10)
                    } label: {
                        HStack {
                            Label("指导尺度", systemImage: "scalemass").foregroundColor(.secondary)
                            Spacer()
                            if disclosedGuidance {
                                Button {
                                    showGuidanceHelp.toggle()
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showGuidanceHelp, arrowEdge: .trailing) {
                                    guidanceHelp($showGuidanceHelp)
                                }
                            } else {
                                Text(guidanceScaleValue)
                            }
                        }
                        .foregroundColor(.secondary)
                    }

                    DisclosureGroup(isExpanded: $disclosedSteps) {
                        CompactSlider(value: $generation.steps, in: 1...150, step: 1) {
                            Text("步骤数")
                            Spacer()
                            Text("\(Int(generation.steps))")
                        }.padding(.leading, 10)
                    } label: {
                        HStack {
                            Label("迭代数量", systemImage: "square.3.layers.3d.down.left").foregroundColor(.secondary)
                            Spacer()
                            if disclosedSteps {
                                Button {
                                    showStepsHelp.toggle()
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showStepsHelp, arrowEdge: .trailing) {
                                    stepsHelp($showStepsHelp)
                                }
                            } else {
                                Text("\(Int(generation.steps))")
                            }
                        }.foregroundColor(.secondary)
                    }

                    DisclosureGroup(isExpanded: $disclosedPreview) {
                        CompactSlider(value: $generation.previews, in: 0...25, step: 1) {
                            Text("预览")
                            Spacer()
                            Text("\(Int(generation.previews))")
                        }.padding(.leading, 10)
                    } label: {
                        HStack {
                            Label("预览迭代数量", systemImage: "eye.square").foregroundColor(.secondary)
                            Spacer()
                            if disclosedPreview {
                                Button {
                                    showPreviewHelp.toggle()
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showPreviewHelp, arrowEdge: .trailing) {
                                    previewHelp($showPreviewHelp)
                                }
                            } else {
                                Text("\(Int(generation.previews))")
                            }
                        }.foregroundColor(.secondary)
                    }

                    DisclosureGroup(isExpanded: $disclosedSeed) {
                        discloseSeedContent()
                            .padding(.leading, 10)
                    } label: {
                        HStack {
                            Label(textFieldLabelSeed, systemImage: "leaf").foregroundColor(.secondary)
                            Spacer()
                            if disclosedSeed {
                                Button {
                                    showSeedHelp.toggle()
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showSeedHelp, arrowEdge: .trailing) {
                                    seedHelp($showSeedHelp)
                                }
                            } else {
                                Text("\(Int(generation.seed))")
                            }
                        }
                        .foregroundColor(.secondary)
                    }

                    if Capabilities.hasANE {
                        Divider()
                            .background(Color.white)
                        DisclosureGroup(isExpanded: $disclosedAdvanced) {
                            HStack {
                                Picker(selection: $generation.computeUnits, label: Text("使用")) {
                                    Text("GPU").tag(ComputeUnits.cpuAndGPU)
                                    Text("神经引擎").tag(ComputeUnits.cpuAndNeuralEngine)
                                    Text("GPU 和 神经引擎").tag(ComputeUnits.all)
                                }.pickerStyle(.radioGroup).padding(.leading)
                                Spacer()
                            }
                            .onChange(of: generation.computeUnits) { units in
                                guard let currentModel = ModelInfo.from(modelVersion: model) else { return }
                                let variantDownloaded = isModelDownloaded(currentModel, computeUnits: units)
                                if variantDownloaded {
                                    updateComputeUnitsState()
                                } else {
                                    mustShowModelDownloadDisclaimer.toggle()
                                }
                            }
                            .alert("需要下载", isPresented: $mustShowModelDownloadDisclaimer, actions: {
                                Button("取消", role: .destructive) { resetComputeUnitsState() }
                                Button("下载", role: .cancel) { updateComputeUnitsState() }
                            }, message: {
                                Text("此设置需要所选模型的新版本。")
                            })
                        } label: {
                            HStack {
                                Label("高级", systemImage: "terminal").foregroundColor(.secondary)
                                Spacer()
                                if disclosedAdvanced {
                                    Button {
                                        showAdvancedHelp.toggle()
                                    } label: {
                                        Image(systemName: "info.circle")
                                    }
                                    .buttonStyle(.plain)
                                    .popover(isPresented: $showAdvancedHelp, arrowEdge: .trailing) {
                                        advancedHelp($showAdvancedHelp)
                                    }
                                }
                            }.foregroundColor(.secondary)
                        }
                    }
                }
            }
            .disclosureGroupStyle(LabelToggleDisclosureGroupStyle())
            
            Toggle("禁用安全检查器", isOn: $generation.disableSafety).onChange(of: generation.disableSafety) { value in
                updateSafetyCheckerState()
            }
                .popover(isPresented: $mustShowSafetyCheckerDisclaimer) {
                        VStack {
                            Text("您已禁用安全检查器").font(.title).padding(.top)
                            Text("""
                                 请确保您遵守 Stable Diffusion 许可证的条款，并且不要将未经过滤的结果暴露给公众。
                                 """)
                            .lineLimit(nil)
                            .padding(.all, 5)
                            Button {
                                Settings.shared.safetyCheckerDisclaimerShown = true
                                updateSafetyCheckerState()
                            } label: {
                                Text("我接受").frame(maxWidth: 200)
                            }
                            .padding(.bottom)
                        }
                        .frame(minWidth: 400, idealWidth: 400, maxWidth: 400)
                        .fixedSize()
                    }
            Divider()
                .background(Color.white)
            
            Button(action: {
                // 触发生成事件的代码
            }) {
                Text("生成")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding([.leading, .trailing, .bottom], 10)

            StatusView(pipelineState: $pipelineState)
        }
        .padding()
        .background(Color.black)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .onAppear {
            modelDidChange(model: ModelInfo.from(modelVersion: model) ?? ModelInfo.v2Base)
        }
    }
    
    fileprivate func discloseSeedContent() -> some View {
        let seedBinding = Binding<String>(
            get: {
                String(generation.seed)
            },
            set: { newValue in
                if let seed = UInt32(newValue) {
                    generation.seed = seed
                } else {
                    generation.seed = 0
                }
            }
        )
        
        return HStack {
            TextField("", text: seedBinding)
                .multilineTextAlignment(.trailing)
                .onChange(of: seedBinding.wrappedValue, perform: { newValue in
                    if let seed = UInt32(newValue) {
                        generation.seed = seed
                    } else {
                        generation.seed = 0
                    }
                })
                .onReceive(Just(seedBinding.wrappedValue)) { newValue in
                    let filtered = newValue.filter { "0123456789".contains($0) }
                    if filtered != newValue {
                        seedBinding.wrappedValue = filtered
                    }
                }
            Stepper("", value: $generation.seed, in: 0...UInt32.max)
        }
        .padding()
        .background(Color.orange.opacity(0.8))
        .cornerRadius(10)
    }
}
