export const meta = {
  name: 'launchhistory-6-features',
  description: 'LaunchHistory 6项需求改造: 冷却/搜索栏/点击穿透/空白退出/拖拽文件夹/多语言',
  phases: [
    { title: '独立改动', detail: '搜索栏重标定 + 点击穿透&空白退出 + 本地化基础（串行避免文件冲突）' },
    { title: '拖拽改造', detail: '0.2s按住进抖动模式 + 三指拖动 + 文件夹逻辑' },
    { title: '字符串本地化', detail: '替换所有硬编码中文为本地化键' },
    { title: '验证', detail: '编译 + 功能逐项检查' },
  ],
}

// 共享上下文：项目根目录和关键文件位置，所有 agent 都需要
const CTX = `
项目: LaunchHistory (fork 自 EricYang801/Launchpad_Back, GPL-3.0, Swift/SwiftUI/AppKit)
源码根目录: /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/
Xcode 工程: /Users/mac/Downloads/Launchpad_Back/Launchpad_Back.xcodeproj
编译命令: cd /Users/mac/Downloads/Launchpad_Back && xcodebuild -project Launchpad_Back.xcodeproj -scheme Launchpad_Back -configuration Release -derivedDataPath /tmp/lh_build build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
部署: cp -R /tmp/lh_build/Build/Products/Release/LaunchHistory.app /Applications/LaunchHistory.app

关键事实:
- 项目用 PBXFileSystemSynchronizedRootGroup，新增 .swift 文件放对目录自动编译，不用改 pbxproj
- 已配置 String Catalog: LOCALIZATION_PREFERS_STRING_CATALOGS=YES, developmentRegion=en
- ENABLE_APP_SANDBOX=NO, ENABLE_HARDENED_RUNTIME=YES
- Logger 用 os_log (OSLog), subsystem=com.Eric-Yang.Launchpad-Back, ⦿ 前缀。Release 也输出
- SourceKit 会报全项目 "Cannot find Logger in scope" 误报，以 xcodebuild 实际结果为准
- 全屏窗口 .screenSaver 层级(borderless), LaunchpadWindow 已重写 canBecomeKey/canBecomeMain=true
- EditModeManager.isEditing 控制抖动编辑模式(@Published var isEditing)
- AppIconView 用 InteractiveIconModifier 处理手势: tapGesture + longPressInteractionGesture(0.5s) + editDragGesture
- 现有文件夹能力: launchpadVM.createFolder(app1:app2:), addAppToFolder(app:folder:), moveItem(withId:to:), insertAppAt(app:index:), removeAppFromFolder
- handleFloatingDrop() 在 ContentView 已有拖放目标判定逻辑(findDropTargetByScreenLocation)
`

const VERIFY_SCHEMA = {
  type: 'object',
  properties: {
    task: { type: 'string' },
    success: { type: 'boolean' },
    filesChanged: { type: 'array', items: { type: 'string' } },
    buildResult: { type: 'string', enum: ['succeeded', 'failed', 'not_attempted'] },
    notes: { type: 'string' },
  },
  required: ['task', 'success', 'buildResult', 'notes'],
}

// ============================================================
// 阶段1: 三个独立改动（串行，因为共享 SettingsView.swift/ContentView.swift）
// ============================================================

phase('独立改动')

// --- 任务1: 搜索栏大小重标定 ---
const searchbarResult = await agent(`${CTX}

【任务: 搜索栏大小重标定】

当前 SearchBarView.swift 用 @AppStorage("searchBarSizeRatio") var sizeRatio: Double = 0.6
所有尺寸 = baseValue * sizeRatio。SettingsView 里 Slider 范围 0.4...1.0 step 0.05, 默认 0.6。

要求（A方案）:
- 以"现在的 ratio 1.0"作为新标准的 50%
- 滑块显示 0%~100%（即 0.0~1.0），但内部映射到 ratio
- 映射关系: 滑块值 0.5 → ratio 1.0（当前默认大小）；滑块值 1.0 → ratio 2.0（最大2倍）；滑块值 0.0 → ratio 0.3（保底，防消失）
- 公式: ratio = 0.3 + sliderValue * 1.4  （验证: slider=0→0.3, slider=0.5→1.0, slider=1.0→1.7... 不对）
- 正确公式: slider 0→ratio0.3, slider 0.5→ratio1.0, slider 1.0→ratio2.0
  线性映射两点定: (0,0.3)和(1,2.0): ratio = 0.3 + slider * 1.7。验证 slider=0.5→0.3+0.85=1.15 ✗
  应该用分段或换基准。最简单: 让 slider 直接代表 ratio，范围 0.3...2.0，默认 1.0，显示文字时换算成百分比。
  换算: 显示百分比 = (ratio - 0.3) / (2.0 - 0.3) * 100。ratio=1.0→41% ✗ 也不对。

重新理清用户需求: "滑块0%~100%，50%=现默认(ratio1.0)，100%=2倍(ratio2.0)，0%附近保底最小ratio0.3，默认50%"
所以 slider 范围 0.0~1.0，默认 0.5。
slider→ratio 映射要让: 0.0→0.3, 0.5→1.0, 1.0→2.0
用两段线性:
  slider in [0, 0.5]: ratio = 0.3 + (slider/0.5) * (1.0-0.3) = 0.3 + slider*1.4
  slider in [0.5, 1.0]: ratio = 1.0 + ((slider-0.5)/0.5) * (2.0-1.0) = 1.0 + (slider-0.5)*2
验证: 0→0.3✓ 0.5→1.0✓ 1.0→2.0✓

实现方式:
- SearchBarView 里 sizeRatio 仍存 ratio(实际值 0.3~2.0)，但 @AppStorage 存的是 slider 值(0.0~1.0, 默认0.5)，内部换算成 ratio 用。
  或者: 改 @AppStorage key 为 "searchBarSlider"，默认 0.5，范围 0...1，在 SearchBarView 里算 ratio。
- SettingsView 的 Slider 改为 in: 0.0...1.0 step: 0.05，selection 绑定 slider 值，显示文字 "当前大小: X%" 用 Int(slider*100)。
- 注意: 旧的 searchBarSizeRatio 默认0.6 的用户数据，新 key 默认0.5。可接受（重置或新用户）。

请改这两个文件:
1. /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/Views/SearchBarView.swift
2. /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/Views/SettingsView.swift (只改 AppearanceSettingsView 的"搜索栏"Section)

改完后用编译命令验证 BUILD SUCCEEDED。返回结果。`, {
  label: '搜索栏重标定',
  phase: '独立改动',
  effort: 'high',
  schema: VERIFY_SCHEMA,
})

// --- 任务2: 点击穿透修复 + 点击空白退出 ---
const clickResult = await agent(`${CTX}

【任务: 修复点击穿透 + 实现点击空白处退出面板】

问题1(点击穿透): 面板打开后(全屏 .screenSaver 层级 borderless 窗口)，鼠标指针仍能与后面UI交互——能点Dock栏打开应用、能点后面窗口的关闭按钮。期望: 面板打开期间所有点击都被面板拦截，不穿透到后面。

问题2(点击空白退出): ContentView.swift 第118-121行有 LaunchpadBackgroundView().onTapGesture { handleEscapeKey() }，但实测无效。期望: 面板打开时轻点空白区域(无图标处)关闭面板。

根因分析:
- LaunchpadBackgroundView 内是 BackgroundView(NSViewRepresentable 包 NSVisualEffectView) + GradientOverlay(View)
- NSVisualEffectView 可能吞掉点击，SwiftUI onTapGesture 收不到
- 全屏 borderless 窗口点击穿透可能因窗口或背景视图未正确参与 hit-testing

请先读这些文件理解现状:
- /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/ContentView.swift (ZStack 结构, 第114-360行)
- /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/Views/BackgroundView.swift
- /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/Launchpad_BackApp.swift (configureMainWindow 全屏配置, 第391-428行)

修复方案(自行判断最佳，以下供参考):
- 点击穿透: 确保全屏窗口的 content view 覆盖整个屏幕且参与 hit-testing。可能需要给背景视图设 .contentShape(Rectangle())，或检查 NSVisualEffectView 是否需要设 acceptsTouchEvents/wantsLayer。窗口层用 screen.frame(已用)。关键是确保窗口本身捕获点击——borderless 窗口默认应该捕获，除非有透明穿透设置。
- 点击空白退出: 在 ZStack 最底层背景上加 .contentShape(Rectangle()).onTapGesture，确保整个背景可点击。或用一个透明的全屏点击层。注意不要影响图标点击(图标在 VStack 上层，会优先接收)。
- 重要: handleEscapeKey() 在搜索栏有文字/编辑模式/文件夹展开时是分级处理，点击空白应该走最终的 hideWindow()。直接调 hideWindow() 或 handleEscapeKey() 都可，但要确保编辑模式下点空白是退出编辑模式而非关面板——参考 ContentView 的 handleEscapeKey() 逻辑(第758行)，它已有分级: 编辑模式→退出编辑, 文件夹→收起, 有搜索→清空, 否则→hideWindow。点击空白应该走同样的 handleEscapeKey()。

改完后编译验证 BUILD SUCCEEDED。返回结果，说明改了哪些文件、怎么改的。`, {
  label: '点击穿透+空白退出',
  phase: '独立改动',
  effort: 'high',
  schema: VERIFY_SCHEMA,
})

// --- 任务3: 本地化基础(建 String Catalog + 语言管理器 + 设置项) ---
const i18nBaseResult = await agent(`${CTX}

【任务: 本地化基础设施 + 语言设置项】

要求: UI 文字支持跟随系统语言。简体中文/繁体中文/英文三选一。系统语言是其他语言时默认英文。

项目已配置 String Catalog (LOCALIZATION_PREFERS_STRING_CATALOGS=YES, developmentRegion=en)，但还没建 .xcstrings 文件。

请完成:
1. 创建 String Catalog 文件: /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/Localizable.xcstrings
   - 这是 JSON 格式的字符串目录。先建一个最小的有效文件(含一个示例 key 如 "search" 的三种语言翻译)，后续任务会往里加键。
   - xcstrings 格式参考: {"sourceLanguage":"en","strings":{"search":{"localizations":{"zh-Hans":{"stringUnit":{"state":"translated","value":"搜索"}},"zh-Hant":{"stringUnit":{"state":"translated","value":"搜尋"}},"en":{"stringUnit":{"state":"translated","value":"Search"}}}}},"version":"1.0"}
   - 注意: 还需在 pbxproj 里注册这个文件到 target。由于项目用 PBXFileSystemSynchronizedRootGroup，放对目录可能自动包含，但 xcstrings 可能需要手动加 PBXFileReference。请检查并确保编译能识别(用 String(localized:"search") 测试)。

2. 创建语言管理器: /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/Settings/LocalizationManager.swift
   - 读取系统语言: Locale.preferredLanguages 或 Bundle.main.preferredLocalizations
   - 逻辑: 系统语言以 zh-Hans 开头→简体, zh-Hant→繁体, en→英文, 其他→英文(默认)
   - 提供一个 @AppStorage("languagePreference") 选项: "system"(默认,跟随系统) / "zh-Hans" / "zh-Hant" / "en"
   - 当为 "system" 时按上面逻辑判断；否则用指定值
   - 暴露当前应使用的语言代码 computed var
   - 注意: macOS app 切换语言通常通过设置 UserDefaults "AppleLanguages" 或重启 app 生效。简化方案: 用 LocalizationManager 返回当前语言，UI 层根据它选择字符串。但 SwiftUI 的 LocalizedStringKey 会自动用 Bundle 的语言。要让手动切换生效，最稳妥是设置 UserDefaults.standard.set([langCode], forKey:"AppleLanguages") 然后提示重启。请实现: 选"跟随系统"时删除 AppleLanguages 自定义；选手动语言时设置 AppleLanguages 并提示需重启 app 生效。

3. 在 SettingsView 的 GeneralSettingsView 加一个"语言"Section:
   - Picker: 跟随系统 / 简体中文 / 繁体中文 / 英文
   - 绑定 @AppStorage("languagePreference") 默认 "system"
   - 选手动语言时显示提示"需要重启应用生效"

注意: 此任务只建基础设施和设置项，不替换现有硬编码字符串(那是下一阶段任务)。但设置项本身的文字先用硬编码中文也行，下一阶段会统一本地化。

改完后编译验证 BUILD SUCCEEDED。返回结果。`, {
  label: '本地化基础',
  phase: '独立改动',
  effort: 'high',
  schema: VERIFY_SCHEMA,
})

// ============================================================
// 阶段2: 拖拽改造（最复杂）
// ============================================================

phase('拖拽改造')

const dragResult = await agent(`${CTX}

【任务: 拖拽改造 - 小米HyperOS风格】

现状(读 /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/Views/AppIconView.swift 的 InteractiveIconModifier, 第142-245行):
- tapGesture: 单击打开应用
- longPressInteractionGesture: LongPressGesture(minimumDuration:0.5).sequenced(before: DragGesture) 长按0.5秒后可拖
- editDragGesture: 编辑模式下 DragGesture(minimumDistance:5) 可拖
- WiggleModifier: isEditing 时图标抖动

要求(参考小米HyperOS):
1. 左键按住图标 0.2秒 → 进入抖动编辑模式(所有图标抖动)，此时可拖动改位置/生成文件夹
   - 进入编辑模式调 editModeManager.enterEditMode() (ContentView 传入的 onLongPress 回调)
   - 抖动用现有 WiggleModifier(isEditing=true)
2. 编辑模式下，点空白背景 → 退出抖动模式(exitEditMode)，恢复正常
   - ContentView 背景的 onTapGesture 已在另一任务里改为调 handleEscapeKey()，编辑模式下点空白会退出编辑(handleEscapeKey 第758行分级逻辑)。确认这条链路通。
3. 编辑模式下拖动图标:
   - 拖到空白位置释放 → moveItem 改位置
   - 拖到另一图标上方释放(中心进入目标~65%区域) → createFolder 生成文件夹
   - 拖到已有文件夹释放 → addAppToFolder
   - 这些 drop 逻辑 ContentView 的 handleFloatingDrop() 已实现，确认 onDragChanged/onDragEnded 回调正确连接
4. 三指拖动: 也支持触发拖拽(三指在触控板拖动)。可用 NSEvent 三指事件或系统三指拖动设置。简化: 在编辑模式下三指拖动等价于鼠标拖动。若难实现可先跳过三指，专注鼠标0.2s按住。
5. 纯点击(按下立即抬起不移动)仍打开应用，不能因支持拖拽破坏点击。

关键改动点:
- InteractiveIconModifier 的 longPressInteractionGesture: minimumDuration 从 0.5 改 0.2
- 确认进入编辑模式后，图标的拖拽手势生效(editDragGesture 在 isEditing 时 minimumDistance:5)
- onLongPress 回调调 enterEditMode，进入后所有图标 isEditing=true 开始抖动
- 注意手势优先级: tapGesture 是 simultaneousGesture，长按0.2s触发后应阻止tap。可能需要调整 highPriorityGesture/simultaneousGesture 顺序。

读这些文件:
- /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/Views/AppIconView.swift (InteractiveIconModifier, AppIconView, FolderIconView, LaunchpadItemView)
- /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/ContentView.swift (onItemTap/onLongPress/onDragChanged 回调, handleFloatingDrop)
- /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/ViewModels/EditModeManager.swift

改完后编译验证 BUILD SUCCEEDED。返回结果，详细说明拖拽手势怎么改的。`, {
  label: '拖拽+抖动+文件夹',
  phase: '拖拽改造',
  effort: 'high',
  schema: VERIFY_SCHEMA,
})

// ============================================================
// 阶段3: 字符串本地化（替换所有硬编码中文）
// ============================================================

phase('字符串本地化')

const l10nResult = await agent(`${CTX}

【任务: 替换所有硬编码中文字符串为本地化键】

前置: 本地化基础已建好(Localizable.xcstrings + LocalizationManager)。此任务把所有硬编码中文/繁体字符串替换为本地化调用。

范围: 项目里约108处含中文字符串字面量，分布在:
- Views/SettingsView.swift (Section标题, Picker选项, Toggle文案, 按钮文字)
- Views/SearchBarView.swift ("搜尋" placeholder)
- Views/AppIconView.swift (contextMenu: "在Finder中顯示","顯示簡介","隱藏", 编辑模式文字)
- Views/FolderExpandedView.swift
- ContentView.swift ("拖動圖標以重新排列", "完成", "重設版面" 等)
- 其他 Views

要求:
1. 把硬编码中文字符串替换为 String(localized: "key") 或 LocalizedStringKey
   - SwiftUI 视图里的字符串字面量(如 Text("搜索"), Section("窗口"), Label("...",systemImage:)) 可以直接用 LocalizedStringKey(自动本地化)，但需确保 key 在 xcstrings 里有翻译
   - 普通字符串(如 Logger, placeholder) 用 String(localized: "key")
2. 把每个用到的 key 加到 Localizable.xcstrings，提供 zh-Hans(简体)/zh-Hant(繁体)/en 三种翻译
   - 现有繁体作为 zh-Hant，简体作为 zh-Hans(把繁体转简体)，英文翻译
3. 命名 key 用英文驼峰或原意(如 "search", "window_mode", "general", "drag_to_rearrange")
4. 不动 Logger 里的字符串(那些是日志不需本地化)
5. 不动代码注释

注意: 这是大量机械工作，但要保证每个 key 都有翻译且拼写正确。繁简转换示例: 搜尋→搜索, 設定→设置, 應用→应用, 開啟→开启, 關閉→关闭, 顯示→显示, 編輯→编辑, 拖動→拖动。

先 grep 找出所有含中文字符串: grep -rn '"[^"]*[一-鿿][^"]*"' /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/ --include="*.swift" | grep -v "//\\|Logger\\|print"
逐个处理。改完后编译验证 BUILD SUCCEEDED。返回结果，列出处理了多少处、xcstrings 加了多少 key。`, {
  label: '字符串本地化',
  phase: '字符串本地化',
  effort: 'high',
  schema: VERIFY_SCHEMA,
})

// ============================================================
// 阶段4: 综合验证
// ============================================================

phase('验证')

const verifyResult = await agent(`${CTX}

【任务: 综合验证 - 编译 + 功能逐项检查】

前面已完成6项改动。请做最终验证:

1. 编译: cd /Users/mac/Downloads/Launchpad_Back && xcodebuild -project Launchpad_Back.xcodeproj -scheme Launchpad_Back -configuration Release -derivedDataPath /tmp/lh_build build 2>&1 | grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"
   - 如有 error，读错误信息，尝试修复(常见: 类型不匹配、漏 import、String Catalog key 缺失)
   - 修复后重新编译直到 BUILD SUCCEEDED

2. 逐项核对6项需求是否在代码中实现(读代码确认，不运行app):
   ① 冷却0.2s: grep "cooldown" MultitouchGestureRecognizer.swift 确认=0.2
   ② 搜索栏重标定: SearchBarView/SettingsView 确认 slider 0~1, 默认0.5, 50%→ratio1.0, 100%→ratio2.0
   ③ 点击穿透修复: 确认全屏窗口/背景捕获点击
   ④ 点击空白退出: ContentView 背景 onTapGesture → handleEscapeKey
   ⑤ 拖拽0.2s进抖动模式: InteractiveIconModifier longPress 0.2, 编辑模式抖动, 文件夹逻辑
   ⑥ 多语言: Localizable.xcstrings 存在, LocalizationManager 存在, SettingsView 有语言项, 字符串已本地化

3. 检查潜在问题:
   - 各 agent 改动是否有冲突或互相破坏(尤其 ContentView.swift 被多个任务改)
   - String Catalog 是否所有 key 都有三种翻译
   - 拖拽手势改动是否破坏了点击打开应用(关键回归)

返回详细验证报告: 每项✓/✗，编译结果，发现并修复的问题，剩余风险。`, {
  label: '综合验证',
  phase: '验证',
  effort: 'high',
  schema: VERIFY_SCHEMA,
})

return {
  searchbar: searchbarResult,
  click: clickResult,
  i18nBase: i18nBaseResult,
  drag: dragResult,
  l10n: l10nResult,
  verify: verifyResult,
}
