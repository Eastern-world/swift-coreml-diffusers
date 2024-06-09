# Swift Core ML Diffusers 🧨

这是一个原生应用，展示了如何在原生Swift UI应用程序中集成Apple的[Core ML稳定扩散实现](https://github.com/apple/ml-stable-diffusion)的开源汉化版本。Core ML端口是从[Hugging Face的diffusers库](https://github.com/huggingface/diffusers)中简化的稳定扩散实现。这个应用程序可用于更快的迭代，或作为任何用例的示例代码。

![应用截图](screenshot.jpg)

首次启动时，应用程序会下载一个包含Stability AI的Stable Diffusion v2基础版本的Core ML版本的压缩存档，来源于[Hugging Face Hub的这个位置](https://huggingface.co/pcuenq/coreml-stable-diffusion-2-base/tree/main)。这个过程需要一段时间，因为需要下载和解压几GB的数据。

为了更快的推断，我们使用了一个非常快的调度器：[DPM-Solver++](https://github.com/LuChengTHU/dpm-solver)，我们已将其从我们的[diffusers DPMSolverMultistepScheduler实现](https://github.com/huggingface/diffusers/blob/main/src/diffusers/schedulers/scheduling_dpmsolver_multistep.py)移植到Swift。

该应用支持使用`coremltools`版本7或更高版本量化的模型。这需要macOS 14或iOS/iPadOS 17。

## 兼容性和性能

- macOS Ventura 13.1, iOS/iPadOS 16.2, Xcode 14.2。
- 性能（初始生成后，速度较慢）
  * 在MacBook Pro M1 Max（64 GB）上的macOS约为8秒。模型：Stable Diffusion v2-base，原始注意力实现，在CPU + GPU上运行。
  * 在iPhone 13 Pro上为23~30秒。模型：Stable Diffusion v2-base，SPLIT_EINSUM注意力，CPU + 神经引擎，启用内存减少。

有关额外性能数字，请查看[这篇博客](https://huggingface.co/blog/fast-mac-diffusers)和[这个问题](https://github.com/huggingface/swift-coreml-diffusers/issues/31)。

量化模型运行更快，但它们需要macOS Ventura 14或iOS/iPadOS 17。

应用程序会尝试猜测最佳硬件来运行模型。您可以使用控制侧边栏中的`高级`部分覆盖此设置。

## 如何运行

在macOS上测试应用程序的最简单方法是[从Mac App Store下载](https://apps.apple.com/app/diffusers/id1666309574)。

## 如何构建

您需要[Xcode](https://developer.apple.com/xcode/)来构建应用。当您克隆仓库时，请使用您的开发团队标识符更新`common.xcconfig`。iOS上需要代码签名才能运行，但目前在macOS上已禁用。

## 已知问题

iPhone上的性能有些不稳定，有时会慢大约20倍，手机会发热。这是因为模型未能调度在神经引擎上运行，所有操作都在CPU中进行。我们尚未确定这个问题的原因。如果您观察到相同的情况，这里有一些建议：
- 断开Xcode连接
- 关闭您不使用的应用程序。
- 让iPhone冷却下来再重复测试。
- 重启您的设备。

## 下一步

- 允许从Hub下载额外的模型。
## 联系我们

如有任何问题或建议，请通过以下邮箱与我们联系：

- Email: [zhenligod@icoud.com]