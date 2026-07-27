export const meta = {
  name: 'launchhistory-8-features-v2',
  description: 'LaunchHistory 新增8项功能: 触发角/垂直滚动开关/重命名/自定义来源/隐藏/隐藏管理/右键扩展(卸载)/三指拖动/语言重启按钮',
  phases: [
    { title: '阶段1: UI独立改动', detail: '垂直滚动开关+语言重启按钮 / 隐藏应用UI管理' },
    { title: '阶段2: 右键菜单扩展', detail: '重命名+隐藏+卸载菜单项' },
    { title: '阶段3: 卸载+自定义来源', detail: '废纸篓卸载服务 + 自定义应用来源' },
    { title: '阶段4: 触发角', detail: 'Hot Corner 4角复选框+NSTrackingArea' },
    { title: '阶段5: 三指拖动', detail: 'MultitouchGestureRecognizer扩展三指追踪+集成' },
    { title: '验证', detail: '编译+8项逐项核对' },
  ],
}

const CTX = `
项目: LaunchHistory (fork 自 EricYang801/Launchpad_Back, GPL-3.0, Swift/SwiftUI/AppKit)
源码根: /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/
Xcode 工程: /Users/mac/Downloads/Launchpad_Back/Launchpad_Back.xcodeproj
编译: cd /Users/mac/Downloads/Launchpad_Back && xcodebuild -project Launchpad_Back.xcodeproj -scheme Launchpad_Back -configuration Release -derivedDataPath /tmp/lh_build build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"

关键架构(已稳定,不要动):
- 项目用 PBXFileSystemSynchronizedRootGroup, 新 .swift 放对目录自动编译, 不用改 pbxproj
- ENABLE_APP_SANDBOX=NO, Hardened Runtime=YES
- LaunchpadWindow 重写 canBecomeKey/canBecomeMain=true; 全屏 level=.screenSaver + borderless; isOpaque 默认 false
- ContentView ZStack 三层: LaunchpadBackgroundView().allowsHitTesting(false) / Color.clear 空白捕获层 / VStack 内容层
- AppIconView InteractiveIconModifier 手势: highPriorityGesture(editDragGesture)+simultaneousGesture(tap)+simultaneousGesture(longPress 0.2s). 不要改这个组合
- MultitouchGestureRecognizer 已用私有 MultitouchSupport.framework 实现四指捏合, 不要动加载逻辑, 只在其上扩展
- Logger 用 os_log, subsystem=com.Eric-Yang.Launchpad-Back, ⦿ 前缀. SourceKit 误报以 xcodebuild 为准
- 已有: AppItem.isHidden 字段, LaunchpadViewModel.hiddenApps([String] stableIdentifier), toggleAppVisibility/isAppHidden 方法
- 已有: viewLayoutMode @AppStorage("viewLayoutMode") horizontalPaging/verticalScroll, viewLayoutModeChanged 通知
- 已有: appContextMenu/folderContextMenu 在 AppIconView.swift
- 已有右键项: showInFinder, getInfo, toggleHide, enterEditMode
- 已有: AppScannerService 扫描系统应用
- SettingsView 已有 Section 结构: 通用(窗口/刷新率/高级/语言), 外观(图标/搜索栏), 手势, 快捷键, 关于
- Localizable.xcstrings + LocalizationManager 已存在, 新增 UI 字符串要加 key 三语翻译
- 回滚点: commit 5ebeb9c / tag v0.5-完整功能稳定版 / 备份目录 LaunchHistory_backup_v0.5_完整版_20260727

新增功能时所有用户可见字符串用 LocalizedStringKey 或 String(localized:), 并在 Localizable.xcstrings 加 key (en/zh-Hans/zh-Hant 三语)。
`

const SCHEMA = {
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
phase('阶段1: UI独立改动')

const uiResult = await agent(`${CTX}

【任务: 需求2 垂直滚动视图开关 + 需求10 语言重启按钮】

需求2: 垂直滚动视图开关
- SettingsView 的"外观"Section 加一个 Picker 或分段控件: "水平分页"(默认) / "垂直滚动"
- 绑定 @AppStorage("viewLayoutMode") 默认 horizontalPaging
- 切换时发 viewLayoutModeChanged 通知 (传对应 ViewLayoutMode 值)
- 默认值: 水平分页
- 注意: 项目里已有 scrollModeToggle (Menu), 这是 ContentView 顶部的快速切换. 设置面板这个是新的明确选项, 两者用同一个 @AppStorage key 保持同步

需求10: 语言切换"退出并重新打开"按钮
- SettingsView 的"语言"Section 现有 needsRestart 提示
- 在提示下方加一个 Button "退出并重新打开" (localized key: restart_app)
- 点击行为: 先 open /Applications/LaunchHistory.app (或用 NSWorkspace.shared.open(appURL)), 再 NSApp.terminate(nil). 顺序很重要: 先调度 open 再 terminate, 否则 app 退出后无法 self-open
- 实现: 用 NSWorkspace.shared.openApplication 或 open(URL), 然后 DispatchQueue.main.asyncAfter(0.1) { NSApp.terminate(nil) }
- 只在 needsRestart=true 时显示该按钮

读 /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/Views/SettingsView.swift 理解现有结构.
改 SettingsView.swift. 新增的 key 加到 Localizable.xcstrings (三语).
编译验证 BUILD SUCCEEDED.`, {
  label: '垂直滚动+语言重启按钮', phase: '阶段1: UI独立改动', effort: 'high', schema: SCHEMA,
})

const hideUiResult = await agent(`${CTX}

【任务: 需求5+6 隐藏应用 UI + 设置面板管理已隐藏应用】

需求5: 右键菜单加"从 Launchpad 隐藏"
- /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/Views/AppIconView.swift 的 appContextMenu 加一项 "从 Launchpad 隐藏" (localized: hide_from_launchpad, 这个 key 可能已存在, 检查)
- 点击调 onToggleHide?(app) (已有回调)
- 注意: 现有代码 appContextMenu 第378行已有 toggleHide 项, 但文案是 show/hide 切换. 确认逻辑正确即可, 不要重复添加

需求6: 设置面板"已隐藏的应用"Section
- SettingsView 加一个 Section "已隐藏的应用" (localized: hidden_apps)
- 从 LaunchpadViewModel 读取 hiddenApps (它是 [String] stableIdentifier 列表)
- 需要把 stableIdentifier 反查成 app 名字/图标: 用 launchpadVM.apps 或 launchpadVM.displayItems 查找
- 列表显示每个隐藏应用的名字, 旁边一个 "显示" 按钮 (localized: show_app)
- 点击 "显示" 调 launchpadVM.toggleAppVisibility(app) 恢复 (需要先找到对应 AppItem)
- 列表为空时显示 "无隐藏应用" (localized: no_hidden_apps)
- 这个 Section 放在哪个 tab? 建议放"通用"或新建. 自行判断, 放外观 tab 也可

注意: LaunchpadViewModel 的 hiddenApps 是 private 还是 internal? 读 /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/ViewModels/LaunchpadViewModel.swift 确认, 必要时暴露只读访问 (var hiddenAppIdentifiers: [String] 或类似). 不要破坏现有持久化逻辑.

读 LaunchpadViewModel.swift + SettingsView.swift + AppIconView.swift.
改 SettingsView.swift (加 Section), 可能小改 LaunchpadViewModel.swift (暴露 hiddenApps 只读), AppIconView.swift 确认菜单项.
新增 key 加 xcstrings 三语.
编译验证 BUILD SUCCEEDED.`, {
  label: '隐藏应用UI+管理', phase: '阶段1: UI独立改动', effort: 'high', schema: SCHEMA,
})

// ============================================================
phase('阶段2: 右键菜单扩展')

const menuResult = await agent(`${CTX}

【任务: 需求3 自定义应用名字 + 需求7 右键菜单结构整理】

需求3: 自定义应用名字
- 右键菜单(appContextMenu) 加 "重命名" 项 (localized: rename, key 可能已存在)
- 点击后弹出输入框: 用 .sheet 或 .alert 配 TextField. 建议 sheet 弹一个 RenameView, 预填当前名字
- 输入新名字确认后保存: UserDefaults key "customNames", 存 [String: String] (stableIdentifier -> customName)
- AppItem 显示名字时优先用 customName: 在 LaunchpadViewModel 或 AppItem 扩展一个 displayName 计算属性, 查 customNames
- 影响范围: 面板图标标签 (IconLabelView 用 app.name), 文件夹内, 搜索匹配(建议也匹配 customName). 不要影响 launchApp (用原 path)
- 重命名后刷新面板显示

需求7: 右键菜单结构整理
- appContextMenu 最终结构(顺序):
  1. 重命名 (需求3, 新)
  2. 从 Launchpad 隐藏 (需求5, 已有/刚加)
  3. 卸载应用 (需求8, 这个由阶段3的 agent 实现, 你这里先加占位项调一个 onUninstall?(app) 回调, 回调暂可空实现或打印日志)
  4. ---
  5. 在 Finder 中显示 (已有)
  6. 简介 (已有)
  7. ---
  8. 进入编辑模式/编辑模式中 (已有)
- folderContextMenu 类似处理: 重命名文件夹(已有 onRenameFolder), 删除文件夹(已有), 进入编辑

实现要点:
- AppIconView 需要新增 onRename: ((AppItem)->Void)? 和 onUninstall: ((AppItem)->Void)? 回调
- LaunchpadItemView 透传这些回调
- ContentView 创建 AppIconView 时传入 onRename/onUninstall 闭包
- onRename 闭包: 弹 sheet, 保存 customNames, 刷新
- onUninstall 闭包: 暂留空或调阶段3的卸载服务(如果阶段3已做完会有, 否则先 NSWorkspace.recycle 占位)

读 AppIconView.swift, ContentView.swift, LaunchpadViewModel.swift, AppItem.swift.
新增 RenameSheet 视图(可放 AppIconView.swift 末尾或新文件).
customNames 读取/保存建议封装到 LaunchpadViewModel (var customName(for app:) / func setCustomName).
新增 key 加 xcstrings 三语.
编译验证 BUILD SUCCEEDED.`, {
  label: '重命名+菜单结构', phase: '阶段2: 右键菜单扩展', effort: 'high', schema: SCHEMA,
})

// ============================================================
phase('阶段3: 卸载+自定义来源')

const uninstallResult = await agent(`${CTX}

【任务: 需求8 卸载到废纸篓 + 需求4 自定义应用来源】

需求8: 卸载应用到废纸篓
- 新建 Services/AppUninstallerService.swift
- 用 NSWorkspace.shared.recycle([URL]) 把 app 的 .app URL 移到废纸篓
- ⚠️ 首次会弹系统授权框(沙盒外操作废纸篓), 这是 macOS 标准行为, 无需特殊处理, 用户自己选择接受
- 卸载后从 Launchpad 移除: 调 LaunchpadViewModel 移除该 app (如有 removeApp 方法用之, 否则刷新扫描)
- 与阶段2的 onUninstall 回调对接: 在 ContentView 的 onUninstall 闭包里调 AppUninstallerService
- 卸载前可加确认 alert "确定将 XX 移到废纸篓?" (localized)

需求4: 自定义应用来源
- SettingsView 加 "应用来源" Section (localized: app_sources)
- "添加应用" 按钮 (localized: add_app) -> 弹 NSOpenPanel, allowedContentTypes=[.application], 目录起始 /Applications
- 选完 .app 后: 路径存 UserDefaults "customAppPaths" ([String])
- 列出已添加的自定义路径, 每个旁边 "移除" 按钮 (localized: remove)
- AppScannerService 扫描时合并 customAppPaths (读 /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/Services/AppScannerService.swift 理解扫描逻辑, 在 scanPaths 或扫描结果合并处加入 customAppPaths)
- 去重: 用 stableIdentifier (bundleID 优先, 退回 path)

读 AppScannerService.swift, SettingsView.swift, LaunchpadViewModel.swift.
新建 AppUninstallerService.swift. 改 AppScannerService.swift (合并自定义路径). 改 SettingsView.swift (应用来源 Section).
对接 ContentView 的 onUninstall (如阶段2已留回调).
新增 key 加 xcstrings 三语.
编译验证 BUILD SUCCEEDED.`, {
  label: '卸载+自定义来源', phase: '阶段3: 卸载+自定义来源', effort: 'high', schema: SCHEMA,
})

// ============================================================
phase('阶段4: 触发角')

const cornerResult = await agent(`${CTX}

【任务: 需求1 触发角启动 Hot Corner】

- SettingsView 加 "触发角" Section (localized: hot_corners)
- 4 个 Toggle 或复选: 左上/右上/左下/右下 (localized: corner_top_left 等)
- 存 UserDefaults: 建议用 4 个 bool key (hotCornerTopLeft 等) 或一个 [String]. 默认全 false (禁用)
- 实现: 新建 Services/HotCornerMonitor.swift
  - 用 NSTrackingArea 或定时器检测鼠标位置(NSEvent.mouseLocation)是否进入某角(比如距角 < 5pt)
  - 进入选定角时调 AppDelegate.showMainWindow() (通过通知或直接调用)
  - 防抖: 鼠标在角内停留 ~0.3s 才触发, 避免路过误触; 触发后冷却 1s
- AppDelegate 启动时根据设置初始化 HotCornerMonitor, 设置变化时重建
- 注意: 鼠标位置检测用 NSEvent.mouseLocation (全局坐标) + NSScreen.frame 判断角落. 不要用 CGEventTap(那个需要权限且复杂)

读 Launchpad_BackApp.swift (理解 AppDelegate.showMainWindow 和初始化流程), SettingsView.swift.
新建 HotCornerMonitor.swift. 改 SettingsView.swift (触发角 Section). 改 Launchpad_BackApp.swift (启动 HotCornerMonitor, 监听设置变化重建).
新增 key 加 xcstrings 三语.
编译验证 BUILD SUCCEEDED.`, {
  label: '触发角', phase: '阶段4: 触发角', effort: 'high', schema: SCHEMA,
})

// ============================================================
phase('阶段5: 三指拖动')

const threeFingerResult = await agent(`${CTX}

【任务: 需求9 三指拖动应用】

效果: 模拟 macOS 系统"三指拖动"辅助功能. 鼠标指针停在应用图标上时, 三指在触控板上滑动 = 拖动该图标(和鼠标按住拖动效果一样: 移动位置/生成文件夹/跨页). 仅在面板显示时生效.

实现方案:
1. 扩展 /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/Services/MultitouchGestureRecognizer.swift
   - 现有四指捏合逻辑保留, 新增三指拖动检测
   - 在 mtContactCallback 里, 当活跃指==3 且各指位移一致(同方向滑动)时, 识别为三指拖动
   - 区分捏合(指间距变化) vs 拖动(整体平移): 三指拖动看整体质心位移, 不是指间距
   - 暴露回调: onThreeFingerDragChanged: ((translation: CGSize, location: CGPoint) -> Void)? 和 onThreeFingerDragEnded: (() -> Void)?
   - 三指拖动开始时记录起始质心, 后续 translation = 当前质心 - 起始质心
   - location 用三指质心的 absolute 坐标(MTTouch.absolute.position)
   - 仅在面板显示时启用(AppDelegate 控制)

2. AppDelegate 桥接
   - setupMultitouchPinch 里同时设置三指拖动回调
   - 回调里: 找到当前鼠标指针下的图标(NSView hit test 或用当前 hover 的图标), 把 translation/location 转发给 ContentView 的拖动状态机
   - 关键: 需要知道"指针下是哪个图标". 可以用 NSEvent.mouseLocation + 当前 grid 布局反查, 或维护一个 hover 状态

3. ContentView 拖动状态机支持三指源
   - 现有 floatingDragState 由 onDragChanged/onDragEnded (鼠标拖动) 驱动
   - 三指拖动走同一套: 三指 dragChanged -> 找到指针下图标作为 draggingItem -> 复用 onDragChanged 逻辑(location 传三指质心) -> 三指 dragEnded -> handleFloatingDrop
   - 注意: 三指拖动不需要"先按下图标", 是指针 hover + 三指滑动即触发

难点:
- 三指拖动开始时确定拖哪个图标: 用 NSEvent.mouseLocation 转窗口坐标, 用 currentGridLayout(in:) 反查 clampedIndex 找到指针下的 item
- 与鼠标拖动不冲突: 三指拖动时 isEditing 可 false, 直接进入拖动(类似长按进编辑后拖动的效果, 但不进编辑模式, 拖完直接 drop)

读 MultitouchGestureRecognizer.swift, Launchpad_BackApp.swift, ContentView.swift (currentGridLayout/findDropTargetByScreenLocation/handleFloatingDrop).
改 MultitouchGestureRecognizer.swift (加三指检测+回调). 改 Launchpad_BackApp.swift (桥接). 改 ContentView.swift (拖动状态机接受三指源).
编译验证 BUILD SUCCEEDED. 这个任务最复杂, 仔细处理坐标转换和状态机.`, {
  label: '三指拖动', phase: '阶段5: 三指拖动', effort: 'high', schema: SCHEMA,
})

// ============================================================
phase('验证')

const verifyResult = await agent(`${CTX}

【任务: 综合验证 8 项新功能】

1. 编译: cd /Users/mac/Downloads/Launchpad_Back && xcodebuild -project Launchpad_Back.xcodeproj -scheme Launchpad_Back -configuration Release -derivedDataPath /tmp/lh_build build 2>&1 | grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"
   - 有 error 就修, 直到 BUILD SUCCEEDED

2. 逐项核对(读代码确认, 不运行):
   ① 触发角: SettingsView 有4角选项, HotCornerMonitor 存在且启动
   ② 垂直滚动开关: SettingsView 有 Picker, 默认水平分页
   ③ 自定义名字: appContextMenu 有重命名, customNames 持久化, displayName 显示
   ④ 自定义来源: SettingsView 有应用来源 Section, AppScannerService 合并 customAppPaths
   ⑤ 隐藏应用: appContextMenu 有隐藏项
   ⑥ 隐藏管理: SettingsView 有已隐藏应用列表+恢复按钮
   ⑦ 右键菜单: 结构完整(重命名/隐藏/卸载/Finder/简介/编辑)
   ⑧ 卸载: AppUninstallerService 存在用 NSWorkspace.recycle, 与 onUninstall 对接
   ⑨ 三指拖动: MultitouchGestureRecognizer 有三指回调, ContentView 接受三指源
   ⑩ 语言重启按钮: SettingsView 有"退出并重新打开"按钮

3. 检查冲突:
   - 多 agent 共享文件: SettingsView.swift, ContentView.swift, AppIconView.swift, Launchpad_BackApp.swift, LaunchpadViewModel.swift, AppScannerService.swift. 检查改动有无互相覆盖/破坏
   - xcstrings key 有无重复或缺失翻译
   - 回归: 点击打开应用、空白退出、四指捏合、长按编辑 是否被破坏(读代码确认手势/事件链没改坏)

返回详细报告: 每项✓/✗, 编译结果, 发现并修复的问题, 剩余风险.`, {
  label: '综合验证', phase: '验证', effort: 'high', schema: SCHEMA,
})

return { ui: uiResult, hideUi: hideUiResult, menu: menuResult, uninstall: uninstallResult, corner: cornerResult, threeFinger: threeFingerResult, verify: verifyResult }
