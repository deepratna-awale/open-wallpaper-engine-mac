Open Wallpaper Engine（修补版）
=========

[English](../../README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | **简体中文** | [繁體中文](README.zh-Hant.md) | [Русский](README.ru.md) | [Polski](README.pl.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [العربية](README.ar.md) | [हिन्दी](README.hi.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](../../LICENSE)

这是 [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) 面向 macOS 的修补分支，新增了场景墙纸渲染并修复了网页墙纸的问题。

> **注：** 本项目与 Steam 上的商业软件 Wallpaper Engine 没有任何关联。这是一款开源的 macOS App，可显示来自 Wallpaper Engine Steam 创意工坊的墙纸素材。 → [ATTRIBUTION.txt](../../ATTRIBUTION.txt)

## 相关项目

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — 适用于 [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) 的 PyQt6 图形界面，其 Steam 创意工坊集成与 UI 设计移植自本 macOS 版本。

## 致谢

本项目建立在以下贡献者的工作之上：

- **[MrWindDog](https://github.com/MrWindDog)** — 上游 [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac) 分支的维护者，添加了新功能并改进了 UI
- **[Haren Chen](https://github.com/haren724)** — [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac) 的原作者，构建了 App 的核心架构（SwiftUI、视频墙纸播放、导入系统、播放列表 UI）
- **[1ris_W](https://github.com/Erica-Iris)** — 中文 i18n 翻译
- **[Klaus Zhu](https://github.com/klauszhu1105)** — 原始标志设计
- **[Chen Chia Yang](https://github.com/Unayung)** — 场景墙纸渲染、网页墙纸修复、Steam 创意工坊集成、多显示器支持、zip 导入
- **[Deepratna Awale](https://github.com/deepratna-awale)** — Metal 场景渲染器与效果管线、GLSL→MSL 着色器转换与缓存、SceneScript 运行时、音频响应渲染、创意工坊／下载功能全面改进、摆放与性能设置、标志重新设计

与原项目相同，本项目采用 [GPL-3.0](../../LICENSE) 许可证。

## 0.9.0 支持的功能

### 场景渲染
- **Wallpaper Engine 自己的着色器** — 图层、效果和材质现在用每张墙纸的原始着色器绘制，并翻译为 Metal，包括创意工坊作者自己制作的效果。
- 合成、全屏和纯色图层，采样其他图层的图层，全部 33 种混合模式，以及更多效果遮罩。
- **忠实的文本排版** — 文本的大小、对齐和位置与 Wallpaper Engine 一致，并支持描边、模糊和投影字体效果。
- **时间线** — 关键帧和纹理动画遵循 Wallpaper Engine 的单次、循环和镜像播放规则。
- 颜色查找表、Wallpaper Engine 的色彩校正，以及墙纸属性中的图像滤镜和颜色选项。
- 由自身动画驱动的 **Puppet Warp** 图像，支持骨骼物理（弹簧、重力、限制）以及挂在骨骼上的对象。

### 3D 与光照
- 支持蒙皮、动画图层、变形目标和根运动的 **3D 模型**。
- 支持相机路径、淡入淡出和抖动的透视场景相机；2D 图层也位于深度之中。
- 支持光照 Cookie、阴影、平面反射、距离雾和高度雾以及体积光的**场景光源**。
- **HDR** — HDR 场景使用 Wallpaper Engine 的 HDR 泛光渲染，“超高（显示器 HDR）”画质会在能够显示 EDR 的显示器上输出 EDR。

### 粒子
- **GPU 粒子** — 所有粒子系统都在 GPU 上以 3D 模拟，并支持 3D 控制点。
- 子系统（包括由父系统粒子触发的子系统）、发射器爆发、延迟和周期性发射，以及从图层图像发射。
- 碰撞（包括与模型骨骼的碰撞）、音频响应，以及绕任意轴的旋转。
- 与墙纸用户属性绑定的粒子设置。

### SceneScript 与媒体
- 完整的 **SceneScript 运行时** — 模块、场景／图层／效果／材质对象模型、动画事件、`localStorage` 和光标命中测试，每张墙纸的脚本在各自的线程上运行。
- 脚本可以创建图层、粒子系统和声音，移动雾，控制泛光，并为木偶和模型摆姿势。
- **正在播放** — 场景墙纸和网页墙纸会收到当前曲目和播放状态（macOS 15.4 或更高版本）。
- 网页墙纸会收到自己的用户属性和实时音频。

### 音频
- 音频频谱按 Wallpaper Engine 的方式以立体声计算。
- **声音图层**按场景时钟播放，并支持与 Wallpaper Engine 一致定位的**空间音频**。

### 显示器与播放
- **按显示器暂停**或**全部暂停**，播放规则按每台显示器分别判断，包括 Wallpaper Engine 的窗口最大化规则。
- 按显示器设置的用户属性，以及“在显示器之间同步属性”。
- 在多台显示器上显示的同一张墙纸只渲染一次，再呈现到每台显示器上。
- 新的画质设置：渲染分辨率、纹理分辨率、按显示器匹配的场景细节、反射、阴影和体积光。
- **安全重启** — 导致 App 卡住或崩溃的墙纸会在下次启动时跳过，并在资源库中标记。

### 创意工坊与资源库
- Wallpaper Engine 的创意工坊筛选：仅显示、分辨率筛选、按“与／或”组合的类型，以及每张卡片上的标签。
- 已安装的墙纸会显示其创意工坊标签并可按标签筛选；仅包含素材或依赖项的项目不会出现在“已安装”中。
- 缺少的创意工坊依赖项会自动下载，不再使用的依赖项会在删除后移除。所有下载都保存到“墙纸存储位置”文件夹。
- “详细信息”中的**重置**会将墙纸的属性及其在场景检查器中的编辑恢复为作者设置的默认值。
- 遵循墙纸设置中的属性条件、文本行和滑块格式。
- 从不存储 Steam 密码，Steam Web API 密钥保存在钥匙串中。

### 界面与语言
- macOS 26 上的 **Liquid Glass** — 带有工具栏、检查器和玻璃控件的原生分栏视图。较早的 macOS 版本保持原有外观。
- **15 种新语言**：德语、法语、西班牙语、巴西葡萄牙语、意大利语、日语、韩语、简体中文和繁体中文、俄语、波兰语、土耳其语、乌克兰语、阿拉伯语和印地语，可在设置的语言选择器中选择。
- 全新的 App 图标，以及跟随菜单栏外观变化的菜单栏图标。

<details>
<summary>0.8.1 版本支持的功能</summary>

### 墙纸播放
- **场景墙纸**使用 Metal 原生渲染，支持图像图层、变换、关键帧时间线、深度排序以及 `scene.json` 中的相机／投影数据。
- **视频墙纸**（`.mp4`、`.webm`）支持播放速率、音量、音视频速度联动，以及可选的随音乐同步缩放／倾斜／饱和度。
- **网页墙纸**（HTML/WebGL）启用了本地文件访问，使 WebGL 纹理和素材能够正确载入，并支持外部嵌入内容（YouTube/Vimeo）。
- **摆放模式** — 充满屏幕、适合于屏幕、居中、拉伸以充满屏幕、缩放。
- **多显示器** — 每台显示器使用不同的墙纸、按屏幕启用／停用、可视化的显示器布局，以及自动检测新连接的显示器。
- **多桌面（Spaces）** — 在所有桌面上连续播放，并提供 `所有桌面` 分配选项。
- **播放规则** — 其他 App 成为焦点时保持运行、静音、暂停或停止；在睡眠／唤醒和切换桌面时行为正确。

### 场景格式支持
- **PKG 解析器**，用于 Wallpaper Engine `PKGV` 归档（scene.json、材质、纹理、着色器）。
- **TEX 解析器**，用于 `TEXV0005` 容器：内嵌的 JPEG/PNG，以及带 mipmap 的 DXT1/DXT3/DXT5，后者通过 Metal 计算着色器在 GPU 上解码。
- **TEXS 精灵时间线**（0001/0002/0003），包括单图集帧矩形和多图像序列。
- **灵活的 scene.json 解码**，可处理 Wallpaper Engine 的多态字段（普通值或 `{"script":…,"value":…}`）。
- 无法提取纹理时**回退到预览图** `preview.jpg/png/gif`。

### 效果与着色器
- **约 48 种原生 Metal 效果**，涵盖扭曲、模糊（标准／精确／径向／运动）、泛光、上帝光与光束、水波／涟漪／焦散／流动、云与雾、胶片颗粒、故障／VHS、色差、颜色键控、变换／倾斜／旋转／漩涡／透视、反射、折射、光泽／微光／闪粉、边缘检测等。
- **音频响应效果** — 脉冲、音频条、随音频同步的色相偏移，以及由实时系统音频频谱数据驱动的超空间跳跃效果。
- **语义材质效果** — 将亮度、对比度、饱和度、曝光、伽马、色相、泛光阈值、泛光和模糊映射为原生 Metal 渲染通道。
- **GLSL → SPIR-V → MSL 转换**在载入时由链接到 App 中的 glslang 和 SPIRV-Cross 完成，支持 COMBO 宏定义、include 解析以及 Metal 缓冲区槽位重新编号。
- **预编译着色器缓存** — 转换后的 `.metal`、编译后的 `.metallib` 以及 `.reflection.json` 附属文件缓存在 `.open-wallpaper-engine/shaders` 下；通过哈希校验，只有发生变化的着色器才会重新转换，并在后台编译，因此不会阻塞渲染。
- **动态效果目录**，读取自 Wallpaper Engine 的 `assets/effects/*/effect.json` 清单，包括多通道效果和通过反射获得的 uniform 绑定。
- **效果遮罩**（每个图层最多 4 张遮罩纹理）、加法混合与 Alpha 混合，以及池化的渲染目标系统。

### 粒子
- 精灵发射器，可随机化寿命、大小、速度、颜色、旋转、角速度、重力、阻力和 Alpha 淡变。
- 高级行为 — 湍流、吸引子、涡旋与 boid 群体运动、静态控制点与跟随光标的控制点、相连的绳索段，以及带 Alpha／大小淡变的拖尾。
- 通过 `.tex-json` 序列实现精灵表帧动画。
- 用于发射速率、阻力和 Alpha 淡变时间的脚本化算子。

### SceneScript 运行时
- 每个图层持久保留的脚本上下文，`init()` 只调用一次，`update(value)` 每帧调用。
- 全局对象：`thisScene`、`thisLayer`、`engine`、`input`、`audio(low, high)`、基于真实数据的 `fft(index)`、`setTimeout`/`setInterval`，以及持久保留的脚本全局变量。
- 完整的 `Vec2`/`Vec3`/`Vec4`/`Mat3`/`Mat4` 数学库，以及 `WEMath`、`WEVector` 和 `WEColor` 辅助工具。
- 从 `assets/scripts/jsmodules` 和 `jsclasses` 载入的 Wallpaper Engine 运行时 JS 模块。
- 光标事件（`cursorMove`/`Down`/`Up`/`Click`/`Enter`/`Leave`）和 `resizeScreen`。
- 脚本可以控制图层的 Alpha、原点、大小、缩放、角度、亮度／颜色、材质常量、效果阈值和粒子速率。
- 去重后的脚本异常日志，并附带重复次数。

### 音频
- 通过 ScreenCaptureKit 捕获系统音频，提供平滑处理的 16 频段频谱、波形以及低音／中音／高音电平。
- 按属性的**音乐同步** — 任何用户属性都可以按可配置的幅度随音频电平调制。

### 用户属性与检查器
- 滑块、复选框、组合框、文本和颜色等项目设置显示在场景边栏中，实时生效，并可从 SceneScript 中读取。
- 针对设置了 `parallaxDepth` 的图层提供鼠标跟踪与视差。

### Steam 创意工坊
- 可按内容分级、类型和风格标签浏览、搜索和筛选，支持热门／最新／最受欢迎／订阅最多排序以及带页码的分页。
- 预览窗口提供设为墙纸、播放和音量控制，并使用有容量上限的缓存；已应用的预览会直接移入资源库，无需重新下载。
- SteamCMD 集成：自动检测、密码／Steam 令牌／缓存会话登录、专用的“下载”标签页、可排队并可重试的下载，以及实时进度。
- 多选、范围选择、经确认后执行的批量下载和删除、持久保存已下载的 ID，以及按 `下载日期` 排序。

### 资源库与设置
- 可从文件夹、`.zip` 包或通过拖放导入。
- 可配置墙纸存储位置，并可迁移现有资源库。
- 状态栏中的“最近使用的墙纸”菜单。
- 性能设置 — 质量、抗锯齿、后处理，以及失去焦点时的播放行为。
- 诊断 — 内置素材的路径、内置着色器编译器的库版本以及着色器缓存统计信息。

</details>

<details>
<summary>0.8.0 及更早版本</summary>

### 多显示器支持
可为每台已连接的显示器分配不同的墙纸，并按屏幕启用或停用。
- **“显示器设置”面板** — 以可视化布局显示所有已连接的屏幕，点按即可选择
- **按屏幕设置墙纸** — 每台显示器可以独立显示不同的墙纸
- **启用／停用开关** — 可按显示器开启或关闭墙纸
- **自动检测** — 连接新显示器时会自动检测并启用

### 多桌面支持
墙纸现在会显示在所有 macOS 桌面（Spaces）上并连续播放，切换桌面时不会中断。

### “最近使用的墙纸”菜单
可从状态栏菜单快速切换墙纸。最近使用的 10 张墙纸会列在其中，点按一次即可切换。

### 播放设置 — 已修复
性能播放设置（其他 App 成为焦点时暂停／静音／停止）现已对所有类型的墙纸正常工作。

### Steam 创意工坊浏览器
无需离开 App，即可直接浏览、搜索和下载 Steam 创意工坊中的墙纸。
- **搜索与筛选** — 按名称搜索，按内容分级（所有人／有争议／成人）、类型（场景／视频／网页）和风格标签筛选
- **排序选项** — 热门、最新、最受欢迎、订阅最多
- **steamcmd 集成** — 自动检测 steamcmd（Homebrew 或自定路径），未找到时提供安装说明
- **Steam 登录** — 支持密码、Steam 令牌和缓存会话认证
- **显示下载进度** — 下载期间实时更新状态（正在认证、下载百分比、正在验证、正在拷贝）
- **安全的默认设置** — 内容分级默认为“所有人”，以过滤成人内容

### zip 导入
可直接从 `.zip` 文件导入墙纸包，无需先手动解压。支持通过“文件”>“导入”和拖放操作使用。

### 多选与批量取消订阅
按住 Cmd 键点按以选择多张墙纸，然后右键点按即可批量取消订阅。

### 墙纸存储隔离
墙纸现在存储在 `~/Documents/OpenWallpaperEngine/` 中，而不是直接存放在“文稿”目录下，避免在新电脑上克隆仓库时出现“error”墙纸。

</details>

<details>
<summary>相对于上游的修补内容</summary>

### 网页墙纸 — 修复灰色／空白渲染
基于 WebGL 的墙纸会渲染为灰色矩形，原因是 `WKWebView` 阻止了对纹理和素材的本地文件访问。

**修复：** 在 WKWebView 配置中启用 `allowFileAccessFromFileURLs` 和 `allowUniversalAccessFromFileURLs`，使 WebGL 着色器能够载入本地纹理文件。

### 场景墙纸 — 从零实现
场景墙纸（Steam 创意工坊中最常见的类型）此前完全没有实现，只会显示“Hello, World!”。

**新实现包括：**
- **PKG 解析器** — 读取 Wallpaper Engine 的 PKGV 归档格式，提取 scene.json、模型、材质和纹理
- **TEX 解析器** — 读取 TEXV0005 纹理容器，提取内嵌的 JPEG/PNG 图像数据，并读取 DXT1/DXT3/DXT5 mipmap
- **Scene JSON 解码器** — 以灵活的解码方式解析 scene.json，可处理 Wallpaper Engine 的多态字段（值可以是普通类型，也可以是 `{"script":..,"value":..}` 对象）
- **Metal 渲染器** — 通过 GPU 纹理合成渲染场景图像图层，并为今后的着色器效果奠定基础
- **GPU DXT 解码** — 在场景载入时通过 Metal 计算着色器展开 DXT1（TEXI 7）、DXT3（TEXI 6）和 DXT5（TEXI 4）纹理
- **精灵粒子** — 渲染常见的 `sphererandom` 精灵发射器，可随机化寿命、大小、速度、Alpha、颜色、旋转、角速度、重力、阻力和 Alpha 淡变
- **高级粒子** — 支持旋转、颜色变化、湍流、静态控制点与跟随光标的控制点、相连的绳索段、拖尾以及 `.tex-json` 精灵表帧动画
- **TEXS 动画** — 解码 TEXS0001/0002/0003 时间线，包括单图集帧矩形和多图像纹理序列
- **场景时间线** — 以 60 FPS 对对象的 Alpha、原点、缩放和角度关键帧进行插值
- **SceneScript 运行时** — 基于 ScreenCaptureKit 系统音频求值表达式和 `export function update(value)` 属性脚本。`thisScene` 计时、`thisLayer.value`、`engine`、输入光标、`audio(low, high)`、基于真实数据的 `fft(index)`、属性查询和持久保留的全局变量共同驱动图像变换、Alpha 和粒子发射速率。
- **持久的 SceneScript 生命周期** — 复用每个图层的脚本上下文，只调用一次 `init()`，并在各帧中调用 `update()`，同时共享 `dt`、帧、鼠标、按钮、修饰键、光标、音频、FFT、属性和图层状态。
- **脚本化粒子算子** — 支持用于粒子发射速率、运动阻力和 Alpha 淡变时间的脚本，并可灵活处理数值／字符串类型的粒子字段。
- **鼠标跟踪与视差** — 对带有 `parallaxDepth` 元数据的图层应用相对于光标的平移和可选的透视缩放；跟随光标的粒子使用同一个场景空间光标。
- **脚本化视觉属性** — 支持通过脚本设置对象亮度／RGB 颜色、材质效果常量、标量／向量变换以及效果阈值覆盖。
- **用户属性** — 在场景边栏中显示文档所述的滑块、复选框、组合框、文本和颜色项目设置，并使数值和布尔值可供 SceneScript 使用
- **内建场景效果** — 在 Metal 渲染器中执行作者设置的 `pulse`、`shake`、`iris` 和 `waterwaves` 效果图条目
- **语义材质效果** — 将亮度、对比度、饱和度、曝光、伽马、色相、泛光阈值、泛光和模糊的常见材质常量与脚本映射为原生 Metal 效果
- **GLSL 着色器转换** — 在载入时通过链接到 App 中的 glslang 和 SPIRV-Cross，将打包的 Wallpaper Engine GLSL 着色器转换为 SPIR-V 和 MSL；转换后的变体缓存在 `~/Library/Caches/com.winddog.wallpaper-engine/shader-variants` 下
- **回退到预览图** — 无法提取纹理时回退到 preview.jpg/png/gif

### 导入 — 修复文件夹导入
导入面板现在可以正确处理单个墙纸文件夹以及包含多个墙纸的父目录。

</details>

## 当前限制

- **应用程序墙纸** — 不支持 `type: "application"` 墙纸，此类墙纸不会运行。
- **3D 模型与骨骼绑定** — 骨骼变换、混合形状、附件和木偶变形绑定（`.mdl`）目前仅为桩实现；受影响的图层会渲染为平面图集。
- **材质脚本函数** — `getMaterial()`、`getMaterialCount()`、`setMaterialProperty()` 和 `executeMaterialFunction()` 仅为桩实现，不执行任何操作或返回空值。
- **自定 GLSL 着色器绑定** — 转换后的 MSL 会在导入时缓存，但依赖 Wallpaper Engine 特有属性、纹理链或不受支持的 include 的着色器不会绑定到运行时 Metal 管线中。常见的泛光、模糊、颜色校正和变换参数会回退到原生 Metal 映射。
- **Metal 缓冲区限制** — 需要超过 Metal 31 个缓冲区槽位的着色器无法转换，并会在当前管线修订版本中被永久标记为不支持。
- **HLSL 着色器** — 与 GLSL 源代码一同提供的仅限 Direct3D 的着色器会被完全跳过。
- **效果架构覆盖范围** — 未知的自定 uniform 名称和任意效果参数架构仍不受支持。
- **SceneScript 一致性** — 并未完全重现所有专有事件名称、输入回调、生命周期边界情况或精确的计时语义。
- **粒子算子覆盖范围** — 常见的脚本化速率、阻力和 Alpha 淡变算子可以正常工作；不常见的算子脚本、自定粒子模块和任意算子架构仅部分支持。
- **外部素材恢复** — 部分创意工坊包引用了下载包中不存在的共享 TEX 素材，需要原版 Wallpaper Engine 的安装文件。
- **部分 JPEG 缩略图** — 少量 TEXB 格式 1 文件包含 macOS 无法解码的非标准 JPEG 数据。
- **性能设置的适用范围** — 质量、抗锯齿和后处理选项是为场景墙纸设计的，对视频墙纸和网页墙纸的作用有限。
- **音频功能需要权限** — 未授予录屏权限时，音频可视化和音频响应的 SceneScript 只会收到静音。

## 支持的墙纸类型

| 类型 | 状态 |
|------|--------|
| 视频（.mp4、.webm） | 可用 |
| 网页（HTML/WebGL） | 可用 |
| 场景 — 图像图层与时间线 | 可用（Metal） |
| 场景 — DXT1/DXT3/DXT5 纹理 | 可用（Metal GPU 解码） |
| 场景 — TEXS 精灵／Alpha 时间线 | 可用 |
| 场景 — 精灵粒子 | 可用 |
| 场景 — 高级粒子 | 部分支持（支持脚本化速率／阻力／淡变） |
| 场景 — 原生 Metal 效果 | 可用（约 48 种效果） |
| 场景 — 转换后的创意工坊 GLSL 效果 | 部分支持（请参阅“当前限制”） |
| 场景 — SceneScript | 部分支持（请参阅“当前限制”） |
| 场景 — 3D 模型／骨骼绑定／木偶变形 | 不支持 |
| 应用程序 | 不支持 |

## 系统要求

### 必需
- **macOS 13.0 或更高版本**（Ventura）。ScreenCaptureKit 音频捕获和 Metal 场景渲染都依赖于此。

### 可选 — 特定功能所需

| 功能 | 要求 | 安装 |
|---------|-------------|---------|
| 浏览／下载 Steam 创意工坊内容 | `steamcmd` | `brew install steamcmd` |
| 音频可视化与音频响应的 SceneScript | 录屏权限 | 设置 → 权限 |

#### 着色器

Wallpaper Engine 以 GLSL 形式提供其效果。当墙纸首次使用这些效果时，它们会由内置于 App 中的 glslang 和 SPIRV-Cross（`Vendor/ShaderToolchain`）转换为 Metal（GLSL → SPIR-V → MSL），随后缓存到磁盘上。无需安装任何内容。如果某个着色器在转换时导致 App 挂起或两次崩溃，之后启动时会跳过它，其他着色器仍会照常转换。

#### Wallpaper Engine 素材

场景使用你在 Steam 上的 Wallpaper Engine 副本中的共享效果、材质、着色器、字体和 SceneScript 运行时；App 不附带这些资源。请在“设置 → 资源”中安装：App 会用 steamcmd 下载你的副本（该账户必须拥有 Wallpaper Engine），仅保留资源和默认墙纸，其余部分会被删除。你也可以选择现有的 Wallpaper Engine 文件夹。视频和网页墙纸无需这些资源即可使用。

## 从源代码构建

### 前提条件
- macOS >= 14.0
- Xcode >= 26.3（macOS 26 SDK）
- Xcode Command Line Tools

### 步骤
```sh
git clone https://github.com/unayung/wallpaper-engine-mac
cd wallpaper-engine-mac
open "OpenWallpaperEngine.xcodeproj"
```

在 Xcode 中，将签名证书更改为你自己的证书或选择“Sign to Run Locally”，然后按下 `Cmd + R` 进行构建并运行。

## 使用方法

### 从 Steam 创意工坊浏览与下载

1. 安装 steamcmd（`brew install steamcmd`），或在 App 中指定已有的二进制文件
2. 切换到 **创意工坊** 标签页，并使用 Steam 账户登录（必须拥有 Wallpaper Engine）
3. 在出现提示时，或在 *设置 → 通用* 中输入 [Steam Web API 密钥](https://steamcommunity.com/dev/apikey)。密钥会经过 Steam 验证并保存在你的钥匙串中；你的 Steam 密码永远不会被存储（steamcmd 会复用它自己的缓存会话）
4. 搜索、筛选，然后在任意墙纸上点按 **下载**

### 从本地文件导入

- **文件夹：** 文件 > 导入 > 来自文件夹的墙纸 — 选择包含 `project.json` 的墙纸文件夹
- **zip：** 文件 > 导入，或拖放包含墙纸包的 `.zip` 文件
- **手动：** 将墙纸文件夹直接拷贝到 `~/Documents/OpenWallpaperEngine/`

## 项目结构

- `OpenWallpaperEngine/Services/SceneParsers/` — PKG、TEX/TEXS 和 scene.json 的解析器与模型
- `OpenWallpaperEngine/Services/SceneEffects/` — 动态效果目录以及作者设置的效果参数范围
- `OpenWallpaperEngine/Scene/Shaders/` — GLSL → SPIR-V → MSL 转换（`ShaderVariant.swift`、`InProcessShaderCompiler.swift`）、缓存和管线归档
- `Vendor/ShaderToolchain/` — glslang 和 SPIRV-Cross 源代码，作为本地包构建到 App 中
- `OpenWallpaperEngine/Scene/Scripting/AudioReactiveScriptEngine.swift` — SceneScript 运行时以及音频／FFT 绑定
- `OpenWallpaperEngine/Audio/AudioLevelTap.swift` — ScreenCaptureKit 系统音频捕获
- `OpenWallpaperEngine/Scene/Rendering/SceneMetalRenderer.swift`、`SceneShaders.metal` — Metal 场景渲染器与着色器库
- `OpenWallpaperEngine/Workshop/SteamCmdService.swift`、`WorkshopAPIService.swift`、`WorkshopViewModel.swift` — Steam 创意工坊浏览与下载
- `OpenWallpaperEngine/Library/WallpaperDirectory.swift`、`ZipImporter.swift`、`WallpaperPackageConverter.swift` — 资源库存储、导入和包转换
- `Scripts/fill-assets-cache.sh` — 开发辅助工具：将 Wallpaper Engine 安装中的资源拷贝到本地文件夹或墙纸存储位置的缓存
- `Scripts/scene-api-coverage.py` — 报告已安装的墙纸使用了哪些 SceneScript API，并与已实现的 API 进行对比
