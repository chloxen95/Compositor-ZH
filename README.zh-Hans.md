# Compositor

> 本文是 [robbietilton/Compositor](https://github.com/robbietilton/Compositor) 的简体中文译本，由本仓库 [chloxen95/Compositor-ZH](https://github.com/chloxen95/Compositor-ZH) 维护。正文只做翻译，不改原意；英文原文更新后本译本可能滞后，以 [README.md](README.md) 为准。

Adobe Photoshop 太贵，而 GIMP 这类工具的操作习惯又让我难以进入状态。所以我做了 Compositor。

目标是从零做出一个功能完整、完全免费且开源的图像编辑器。我以前用 Photoshop 做合成和后期处理，所以 Compositor 就是围绕这套工作流构建的——它具备做出一张像素级精确成品图所需的工具。

因为它是开源的，你可以下载 Xcode 工程，按自己的工作流增删或修改任何功能。

## 安装

### 下载
从 [robbietilton.com/compositor](https://robbietilton.com/compositor) 获取 Compositor，或直接从 [GitHub Releases](https://github.com/robbietilton/Compositor/releases/latest) 下载最新版本。

### Homebrew

```sh
brew install --cask robbietilton-compositor
```

## 功能

### 图层
- 图层与图层组，支持不透明度，以及 Photoshop 全套混合模式（顺序与 Photoshop 一致）——图层组的不透明度会对组内所有内容生效
- 图层蒙版：可在画布任意位置绘制、填充、反相、模糊与羽化，不受图层自身像素范围限制；可链接或断开链接，让蒙版独立变换
- 剪贴蒙版与图层组蒙版
- 调整图层：色相/饱和度、色阶、曲线、曝光度、渐变映射、颗粒、黑白、色彩平衡、反相；滤镜图层：高斯模糊、动感模糊、渐变模糊、锐化、杂色、晕影、泛光、RGB 分离、镜头效果、色调对比度
- 图层样式：描边、投影、颜色叠加、内阴影、外发光、内发光，由 GPU 渲染，随时可编辑
- 向下合并、合并图层与合并组（⌘E）
- 复制、就地重命名、拖拽调整顺序与嵌套；按住 Option 拖拽可复制；图层面板提供右键菜单
- 复制粘贴整个图层与图层组（无选区时 ⌘C/⌘V），可在同一项目内或项目之间进行，也可直接在项目之间拖拽

### 变换
- 非破坏性的移动、缩放、旋转与翻转——无论缩到多小，图像都保持完整分辨率
- 自由扭曲（按住 ⌘ 拖拽手柄），按住 Shift 可锁定单轴
- 可同时变换多个图层或整个图层组
- 吸附到画布与图层的边缘和中心，并配合参考线
- 位置、尺寸、缩放与角度的精确数值，可用方向键步进
- 翻转图层与翻转画布，支持水平与垂直
- 对齐与分布图层，基准可为其他图层、选区或画布，入口在移动工具的工具条或「图层」菜单

### 选区
- 矩形与椭圆选框、自由套索与多边形套索，以及魔棒/对象工具——魔棒按颜色选择，对象模式则描摹所点击的对象（Tab 键切换）
- 选择主体，以及对任意选区执行扩展、收缩与羽化
- 可加选、减选、移动选区轮廓，或移动与复制选区内的像素
- 将图层像素或蒙版载入为选区
- 内容识别填充，还能把图像延伸到画布之外

### 绘画与修饰
- 画笔支持大小、硬度、不透明度与平滑，可在绘制或擦除模式间切换（B 与 E），按住 Shift 绘制直线
- 在数位板上可用笔压控制画笔的大小与不透明度
- 污点修复画笔（内容识别）
- 仿制图章，可对齐或不对齐，可采样单个图层或所有图层
- 模糊工具，可作用于像素或蒙版
- 渐变工具与形状工具（矩形、圆角矩形、椭圆与直线），保持可编辑，不会被栅格化
- 文字工具（T）：在可拖拽、可缩放的多行段落框中就地编辑；字体、字号、颜色、对齐与间距在工具头栏设置；可变换文字，也可用作剪贴蒙版
- 吸管与完整的拾色器

### 调整与滤镜
- Camera Raw 滤镜：光照、颜色、曲线、颜色混合器、颜色分级、细节、光学与几何，位于画布旁的面板中；每个分区都可从标题处恢复默认值
- 色阶（含自动）、曲线、色相/饱和度、曝光度、渐变映射、颗粒、黑白、色彩平衡与反相
- 高斯模糊与动感模糊，可扩散出图层边界
- 锐化、添加杂色、晕影、泛光、抖动、扫描线、RGB 分离、镜头效果（变形光斑、星芒、柔雾、棱镜，以及圆形、六边形、椭圆与猫眼形状的散景）、色调对比度、轮廓光（主体背后最多三盏彩色光源，辉光会把主体包裹进光里）、镜头校正与移除背景
- 实时预览；存在选区时仅作用于选区内
- 上次滤镜操作（⌃⌘F）以相同参数再次运行上一次的滤镜

### 画布与文件
- 多项目标签页
- 搜索命令（⌘F）：按名称查找所有菜单命令与工具，用法类似 Raycast 或 Obsidian，回车即可执行
- 切换全屏（F）：整屏纯黑只留画布，所有面板收起；按 F 或 Esc 恢复
- 标尺（⌘R）、从标尺拖出的参考线、可调间距与细分的布局网格，以及针对参考线、网格、图层与文档边界的「对齐到」
- 裁剪支持吸附，比例包含 3:4 与 9:16，按住 Option 可对称裁剪；存在选区时，裁剪框从选区开始
- 画布大小、图像大小与裁切
- 窗口高度不足时，工具栏自动变为两列
- 缩放至 300% 以上时，画布角落出现导航器小地图：整份文档缩略显示，并用方框标出当前视图；点击或拖拽即可移过去（视图 › 导航器）
- 缩小时采用清晰的高质量降采样，放大时显示像素网格
- 导入 JPEG、PNG、HEIC、TIFF、WebP、SVG、PDF（每页各自成层，按 300 DPI 或适配画布）、动画 GIF（单图层多帧，帧条显示在画布下方，可播放、绘制、复制、删除与调整时长）、相机 RAW（先经过显影步骤），以及 Photoshop PSD 与 PSB（8 位 RGB，不支持 CMYK）。每个 Photoshop 画板各自打开一个标签页；图层组、蒙版、混合模式、填充矩形/椭圆与简单横排文字保持可编辑；其他矢量对象与直排文字会转为像素。应用之前会先显示转换报告
- 大型文档：内存预算随你的 Mac 配置伸缩；过大的 Photoshop 文件会把图层裁切到画布尺寸后再打开
- 导出 PNG（⇧⌘E）、导出 JPEG（⇧⌥⌘S），以及导出为（⇧⌥⌘W）：可选 PNG、JPEG、按印刷尺寸输出的单页 PDF，或有 GIF 图层时导出动画 GIF，可按需缩放，并提供实时预览、JPEG 质量与文件大小；「导出为」中的通道打包可把多个图层打包进一张 PNG 的红、绿、蓝与 Alpha 通道，用于游戏贴图，RGB 分离的「分离到图层」则把一个图层拆回这四个通道；合并拷贝
- 项目保存期间可继续工作
- 全程使用 Photoshop 风格快捷键，可在「编辑 › 键盘快捷键」中重新映射
- 拖拽数字旁的标签即可擦洗调整数值，与 Photoshop 一致
- 自动更新，已签名并公证

### 与 AI 智能体协作
- AI 智能体与脚本可直接构建、编辑项目：`.comp` 就是一个装着 PNG 图层与一个清单文件的文件夹，项目处于打开状态时，文件一写入画布就会实时更新。详见[编写 Compositor 项目](docs/writing-comp-files.md)

## 系统要求

- macOS 26.0 或更高版本，Apple 芯片的 Mac
- Xcode 26 或更高版本（从源码构建时需要）

## 翻译

Compositor 目前仅有英文版，且不接受翻译相关的 Pull Request。项目由一人维护，此后每新增一条文案都需要翻译，而我看不懂的语言也无法评审。等应用稳定后我会重新考虑这件事；在那之前，请不要提交本地化 PR。

> 本仓库是独立的简体中文分支，同样不向上游提交本地化 PR。

## 其他平台

Compositor 仅支持 macOS。以下非官方移植由他人制作，未经作者评审，也不由作者提供支持，相关问题请向他们反馈：

- [CompositorWindows](https://github.com/Cengokill/CompositorWindows)，作者 [@Cengokill](https://github.com/Cengokill)：Windows
- [Composa](https://github.com/dvdstelt/Composa)，作者 [@dvdstelt](https://github.com/dvdstelt)：Windows 与 Linux
- [CompositorLX](https://github.com/ClaudiuJitea/compositorLX)，作者 [@ClaudiuJitea](https://github.com/ClaudiuJitea)：Linux

更多项目列于 [#23（Windows）](https://github.com/robbietilton/Compositor/issues/23) 与 [#19（Linux）](https://github.com/robbietilton/Compositor/issues/19)。

## 构建

打开 `Compositor.xcodeproj`，运行 **Compositor** scheme。

## 发布

`scripts/release.sh` 会构建 Release 版本，用 Developer ID 签名，公证并装订，最后打包为 `dist/Compositor-<version>.dmg`。

它需要以下条件，且都不放在本仓库中：

- 登录钥匙串中的一份 **Developer ID Application** 证书
- 用 `xcrun notarytool store-credentials "compositor-notary" …` 保存的公证凭据
- [`create-dmg`](https://github.com/create-dmg/create-dmg)（`brew install create-dmg`）

## 许可

MIT —— 见 [LICENSE](LICENSE)。
