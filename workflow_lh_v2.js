export const meta = {
  name: 'launchhistory-features-v2-gpt-plan',
  description: 'LaunchHistory 10项新功能 (按GPT分工方案: 数据层/系统服务/布局/设置页/菜单/本地化/三指拖动)',
  phases: [
    { title: '阶段1: 数据层(A)' },
    { title: '阶段1: 系统服务(B)' },
    { title: '阶段1: 布局模式(C)' },
    { title: '阶段2: 设置页(D)' },
    { title: '阶段2: 右键菜单(E)' },
    { title: '阶段3: 本地化(F)' },
    { title: '阶段4: 三指拖动(G)' },
    { title: '验证' },
  ],
}

const CTX = `
项目: LaunchHistory (fork 自 EricYang801/Launchpad_Back, GPL-3.0, Swift/SwiftUI/AppKit)
源码根: /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/
编译: cd /Users/mac/Downloads/Launchpad_Back && xcodebuild -project Launchpad_Back.xcodeproj -scheme Launchpad_Back -configuration Release -derivedDataPath /tmp/lh_build build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"

架构(已稳定,严禁修改):
- PBXFileSystemSynchronizedRootGroup, 新 .swift 放对目录自动编译
- ENABLE_APP_SANDBOX=NO, Hardened Runtime=YES
- LaunchpadWindow canBecomeKey/canBecomeMain=true; 全屏 level=.screenSaver+borderless; isOpaque 默认 false
- ContentView ZStack 三层: 背景 allowsHitTesting(false) / Color.clear 空白捕获 / VStack
- AppIconView InteractiveIconModifier 手势: highPriorityGesture(editDragGesture)+simultaneousGesture(tap)+simultaneousGesture(longPress 0.2s). 严禁改这个组合和 didLongPress 修复
- MultitouchGestureRecognizer 已实现四指捏合(私有 MultitouchSupport.framework). 严禁动 dlopen/MTDeviceCreateList/MTRegisterContactFrameCallback/四指捏合判定/冷却
- Logger 用 os_log, subsystem=com.Eric-Yang.Launchpad-Back, ⦿ 前缀. SourceKit 误报以 xcodebuild 为准
- 已有: AppItem(stableIdentifier=bundleID空时退回path, isHidden), LaunchpadViewModel.hiddenApps([String]), toggleAppVisibility/isAppHidden
- 已有: viewLayoutMode @AppStorage("viewLayoutMode") horizontalPaging/verticalScroll, viewLayoutModeChanged 通知
- 已有: appContextMenu/folderContextMenu 在 AppIconView.swift (现有项: showInFinder/getInfo/toggleHide/enterEditMode)
- 已有: AppScannerService 扫描系统应用
- SettingsView 已有 Section: 通用(窗口/刷新率/高级/语言), 外观(图标/搜索栏), 手势, 快捷键, 关于
- Localizable.xcstrings + LocalizationManager 已存在

严格文件所有权(每个 agent 只能改自己负责的文件, 不顺手动别人的):
- AppItem.swift / LaunchpadViewModel.swift / AppScannerService.swift -> 数据层 agent
- HotCornerMonitor.swift(新) / AppUninstallerService.swift(新) -> 系统服务 agent
- ContentView.swift -> 布局 agent (之后三指 agent 也会改)
- SettingsView.swift / Launchpad_BackApp.swift -> 设置页 agent (之后三指 agent 也会改)
- AppIconView.swift -> 菜单 agent
- Localizable.xcstrings -> 只有本地化 agent 改
- MultitouchGestureRecognizer.swift -> 只有三指 agent 改

新增 UI 字符串: 各 agent 在代码里用 LocalizedStringKey/String(localized:) 引用确定 key, 但不要自己改 Localizable.xcstrings(由本地化 agent 统一加). key 命名用点分: settings.xxx / menu.xxx / app.xxx
`

const SCHEMA = {
  type: 'object',
  properties: {
    task: { type: 'string' },
    success: { type: 'boolean' },
    filesChanged: { type: 'array', items: { type: 'string' } },
    buildResult: { type: 'string', enum: ['succeeded', 'failed', 'not_attempted'] },
    newLocalizationKeys: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
  required: ['task', 'success', 'buildResult', 'notes'],
}

// ============================================================
phase('阶段1: 数据层(A)')

const agentA = await agent(`${CTX}

【Agent A: 数据模型与持久化】
负责需求: 3(自定义名字数据) / 4(自定义来源存储+扫描合并) / 5(隐藏数据接口复核) / 6(隐藏管理数据接口) / 8(卸载后数据移除接口)
独占文件: Models/AppItem.swift, ViewModels/LaunchpadViewModel.swift, Services/AppScannerService.swift
可新增: Services/CustomNameStore.swift, Services/CustomAppSourceStore.swift
严禁改: SettingsView/AppIconView/ContentView/Launchpad_BackApp/MultitouchGestureRecognizer/Localizable.xcstrings

接口要求(供后续 agent 调用):
- AppItem 增加 originalName 和 customName: String? ; displayName 计算属性(customName 优先). 不要让 displayName 每次读 UserDefaults, 由 ViewModel 更新对应 AppItem.customName 触发刷新
- LaunchpadViewModel 暴露:
  func renameApp(_ app: AppItem, to newName: String?)  // nil/空=恢复原名
  func displayName(for app: AppItem) -> String
  func addCustomAppPath(_ url: URL)
  func removeCustomAppPath(_ url: URL)
  var customAppPaths: [URL] { get }
  var hiddenAppEntries: [HiddenAppEntry] { get }  // 含名字/路径供设置页显示
  func removeAppFromLaunchpad(_ app: AppItem)  // 卸载成功后调用

关键:
- hiddenApps 持久化已有, 复核接口. 隐藏应用不能从扫描结果彻底删除, 保留 allApps(含隐藏) + visibleApps(过滤后). hiddenAppEntries 反查名字用 allApps
- customNames 存 UserDefaults "customNames" [String:String] (stableIdentifier->name)
- customAppPaths 存 UserDefaults "customAppPaths" [String]
- AppScannerService 扫描时合并 customAppPaths, 去重用 stableIdentifier
- 新建 HiddenAppEntry 结构 (id/name/path) 供设置页用

读 AppItem.swift, LaunchpadViewModel.swift, AppScannerService.swift 理解现状.
编译验证 BUILD SUCCEEDED. 列出新增的 localization key(代码里引用但没加到 xcstrings 的).`, {
  label: 'A:数据层', phase: '阶段1: 数据层(A)', effort: 'high', schema: SCHEMA,
})

// ============================================================
phase('阶段1: 系统服务(B)')

const agentB = await agent(`${CTX}

【Agent B: 系统服务】
负责需求: 1(HotCornerMonitor服务) / 8(AppUninstallerService)
独占新增文件: Services/HotCornerMonitor.swift, Services/AppUninstallerService.swift
严禁改: 任何现有 UI 文件(AppIconView/SettingsView/ContentView/Launchpad_BackApp等). 只实现服务, 不接入

HotCornerMonitor:
enum HotCorner: String, Codable, CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }
final class HotCornerMonitor {
  var enabledCorners: Set<HotCorner>
  var onTrigger: (() -> Void)?
  func start(); func stop()
}
行为: 定时读 NSEvent.mouseLocation, 用每个 NSScreen.frame 判断角落(多屏支持, 含负坐标). 停留~0.3s 触发, 冷却1s, 离开重置, 同次停留不连续触发. 默认无启用角.

AppUninstallerService:
final class AppUninstallerService {
  func moveToTrash(appURL: URL, completion: @escaping (Result<Void, Error>) -> Void)
}
用 NSWorkspace.shared.recycle([appURL]). 仅 recycle 成功后调 completion(.success). 失败(无权限/文件不存在/系统保护)调 .failure. 不在此服务里碰 ViewModel.

读 Launchpad_BackApp.swift(只读, 理解 AppDelegate 结构但不改).
编译验证.`, {
  label: 'B:系统服务', phase: '阶段1: 系统服务(B)', effort: 'high', schema: SCHEMA,
})

// ============================================================
phase('阶段1: 布局模式(C)')

const agentC = await agent(`${CTX}

【Agent C: 垂直滚动布局模式】
负责需求: 2(垂直滚动视图)
独占文件: ContentView.swift
严禁改: SettingsView/AppIconView/Launchpad_BackApp/MultitouchGestureRecognizer/Localizable.xcstrings

现状: ContentView 已有 viewLayoutMode(@AppStorage) 和 if viewLayoutMode == .horizontalPaging {} else { VerticalScrollView(...) } 分支. 设置页 Picker 由 Agent D 做, 你只确保 ContentView 的两种模式都正确.

任务:
- 确认 ContentView 两种布局切换正常, 默认 horizontalPaging
- 垂直模式必须保留: 应用点击/长按编辑/拖动/文件夹/搜索过滤/点击空白退出/背景三层结构/AppIconView 手势组合
- 若现有 VerticalScrollView 有缺陷(如拖动冲突)修复, 但不重构 InteractiveIconModifier
- 垂直模式下编辑模式拖动不应被 ScrollView 抢走(可能需要 ScrollView 同时允许内容拖动)

读 ContentView.swift, Views/VerticalScrollView.swift.
只改 ContentView.swift(和必要时的 VerticalScrollView.swift, 但 VerticalScrollView 不在他人独占列表, 可改).
编译验证.`, {
  label: 'C:布局模式', phase: '阶段1: 布局模式(C)', effort: 'high', schema: SCHEMA,
})

// ============================================================
phase('阶段2: 设置页(D)')

const agentD = await agent(`${CTX}

【Agent D: 设置页与生命周期接入】
负责需求: 1(触发角UI+启动接入) / 2(布局Picker) / 4(自定义来源UI) / 6(隐藏管理UI) / 10(退出重开按钮)
独占文件: SettingsView.swift, Launchpad_BackApp.swift
依赖(已由前面 agent 完成, 直接调用):
  - Agent A: LaunchpadViewModel.customAppPaths/addCustomAppPath/removeCustomAppPath/hiddenAppEntries/toggleAppVisibility(已有)
  - Agent B: HotCornerMonitor(enabledCorners/onTrigger/start/stop)
  - Agent C: viewLayoutMode 值(horizontalPaging/verticalScroll)
严禁改: AppIconView/ContentView/MultitouchGestureRecognizer/Localizable.xcstrings/AppScannerService/LaunchpadViewModel

任务:
1. 触发角 Section(放"手势"或"通用"tab): 4 个 Toggle(左上/右上/左下/右下). 存 4 个 bool @AppStorage(hotCornerTopLeft 等) 或数组. AppDelegate 启动 HotCornerMonitor, onTrigger={showMainWindow()}, 设置变化时更新 enabledCorners
2. 布局 Picker(外观 Section): "水平分页"(默认)/"垂直滚动", 绑定 viewLayoutMode, 切换发 viewLayoutModeChanged 通知
3. 应用来源 Section: "添加应用"按钮->NSOpenPanel(只允许.app)->调 addCustomAppPath. 列出 customAppPaths 每个旁"移除"按钮->removeCustomAppPath. 重复不添加
4. 已隐藏应用 Section: 用 hiddenAppEntries 列表, 每项名字+"显示"按钮->toggleAppVisibility 恢复. 空时"无隐藏应用"
5. 语言 Section: needsRestart 提示下加"退出并重新打开"按钮. 动作: NSWorkspace.shared.open(appURL) 后 DispatchQueue.main.asyncAfter(0.1){NSApp.terminate(nil)}. 注意: 可能需用 /usr/bin/open -n 强制新实例, 第一版先按此实现, 标注待验收

读 SettingsView.swift, Launchpad_BackApp.swift, LaunchpadViewModel.swift(只读接口), HotCornerMonitor.swift(只读接口).
改 SettingsView.swift + Launchpad_BackApp.swift.
编译验证. 列出新增 localization key.`, {
  label: 'D:设置页', phase: '阶段2: 设置页(D)', effort: 'high', schema: SCHEMA,
})

// ============================================================
phase('阶段2: 右键菜单(E)')

const agentE = await agent(`${CTX}

【Agent E: 右键菜单和交互UI】
负责需求: 3(重命名sheet) / 5(隐藏菜单项) / 7(菜单顺序) / 8(卸载确认+服务调用)
独占文件: AppIconView.swift
可新增: Views/RenameAppSheet.swift, Views/UninstallConfirmationView.swift
严禁改: InteractiveIconModifier 手势组合/didLongPress/点击链/编辑拖动逻辑. 严禁改 SettingsView/ContentView/Launchpad_BackApp/MultitouchGestureRecognizer/Localizable.xcstrings/LaunchpadViewModel

依赖: Agent A(renameApp/displayName/removeAppFromLaunchpad), Agent B(AppUninstallerService.moveToTrash)

任务:
1. appContextMenu 最终顺序: 重命名 / 从Launchpad隐藏 / 卸载应用 / 分隔 / 在Finder显示 / 简介 / 分隔 / 进入编辑模式
2. AppIconView 新增回调: onRename: ((AppItem)->Void)?, onUninstall: ((AppItem)->Void)?
3. 重命名: 弹 RenameAppSheet(预填 displayName), 空字符串=恢复原名, 调 renameApp. 立即刷新
4. 卸载: 弹确认 alert "确定将 XX 移到废纸篓?" -> 调 AppUninstallerService.moveToTrash -> 成功调 removeAppFromLaunchpad -> 失败显示错误不移除
5. 隐藏项: 调 onToggleHide(已有)
6. folderContextMenu: 重命名文件夹(已有 onRenameFolder)/删除文件夹(已有)/进入编辑
7. LaunchpadItemView 透传 onRename/onUninstall; ContentView 创建时传闭包(但 ContentView 是 Agent C 独占! 所以你只能在 AppIconView/LaunchpadItemView 定义回调参数, ContentView 的对接由后续处理. 先确保 AppIconView 自身完整, 用 // TODO: ContentView 接入 标注)

注意坐标: 不要碰 .contentShape/.gesture/.simultaneousGesture/.highPriorityGesture. 只改 appContextMenu/folderContextMenu/sheet/alert/回调声明.

读 AppIconView.swift, LaunchpadViewModel.swift(只读 renameApp/removeAppFromLaunchpad 接口), AppUninstallerService.swift(只读).
改 AppIconView.swift, 新建 RenameAppSheet.swift.
编译验证. 列出新增 localization key.`, {
  label: 'E:右键菜单', phase: '阶段2: 右键菜单(E)', effort: 'high', schema: SCHEMA,
})

// ============================================================
phase('阶段3: 本地化(F)')

const agentF = await agent(`${CTX}

【Agent F: 本地化】
独占文件: Localizable.xcstrings
任务: 汇总前面所有 agent 新增的 localization key, 每个加 en/zh-Hans/zh-Hant 三语翻译. 检查 %@/%d/%lld 类型一致. 检查源码无残留硬编码用户可见中文(Logger/注释除外).

步骤:
1. grep 源码找所有 LocalizedStringKey 和 String(localized:) 引用的 key: grep -rn 'LocalizedStringKey\|String(localized:' /Users/mac/Downloads/Launchpad_Back/Launchpad_Back/ --include='*.swift'
2. 读 Localizable.xcstrings 看已有 key
3. 找出缺失的 key, 加三语翻译
4. 繁简转换正确(搜尋→搜索 简体; 不把简体当繁体)
5. 带占位符的 key 三语占位符一致

读 Localizable.xcstrings + 全项目源码找 key.
只改 Localizable.xcstrings.
编译验证 BUILD SUCCEEDED. 输出新增 key 数量和总数.`, {
  label: 'F:本地化', phase: '阶段3: 本地化(F)', effort: 'high', schema: SCHEMA,
})

// ============================================================
phase('阶段4: 三指拖动(G)')

const agentG = await agent(`${CTX}

【Agent G: 三指拖动专项】
负责需求: 9(三指拖动应用)
效果: 模拟 macOS 系统"三指拖动". 指针停在图标上时, 三指滑动=拖动该图标(移动/生成文件夹/跨页). 仅面板显示时生效.
可改文件: MultitouchGestureRecognizer.swift, ContentView.swift, Launchpad_BackApp.swift
建议新增: Services/ThreeFingerDragCoordinator.swift, Models/ThreeFingerDragEvent.swift
严禁: 动 dlopen/MTDeviceCreateList/MTRegisterContactFrameCallback/四指捏合判定/四指冷却/设备启停. 严禁改 AppIconView 的 InteractiveIconModifier 手势. 严禁改 SettingsView.

步骤(每步验证四指捏合无回归):
1. MultitouchGestureRecognizer 加三指回调:
   var onThreeFingerDragBegan: ((CGPoint) -> Void)?
   var onThreeFingerDragChanged: ((CGPoint) -> Void)?
   var onThreeFingerDragEnded: (() -> Void)?
   判定: 活跃指==3, centroid 明显位移 + averageRadius 变化小 = 平移(拖动); averageRadius 变化大 = 捏合(忽略, 让四指捏合处理). 加最小位移阈值/捏合容差/连续帧确认. 手指数变化立即结束. 回调切主线程.
   location 用三指质心 absolute 坐标.
2. ThreeFingerDragCoordinator: 集中坐标转换. 三套坐标统一: NSEvent.mouseLocation(全局) / AppKit窗口 / SwiftUI Grid. 拖动开始用 NSEvent.mouseLocation 反查指针下图标(不要用触点中心).
   指针下图标反查: 建议用 GeometryPreferenceKey 缓存 [stableIdentifier: CGRect] 全局frame, 鼠标位置命中测试(不要简单行列推算, 因多屏/scroll offset/page offset/搜索结果索引变化).
3. AppDelegate 桥接: setupMultitouchPinch 里设三指回调 -> ThreeFingerDragCoordinator -> ContentView 拖动状态机. 仅面板显示时启用.
4. ContentView 拖动状态机接受三指源: 三指 began->找指针下图标作 draggingItem(复用 onDragChanged 逻辑, location 传鼠标位置)->changed 更新->ended 调 handleFloatingDrop. 三指拖动不进编辑模式, 拖完直接 drop.

读 MultitouchGestureRecognizer.swift, ContentView.swift(currentGridLayout/findDropTargetByScreenLocation/handleFloatingDrop/floatingDragState), Launchpad_BackApp.swift.
改 MultitouchGestureRecognizer.swift, ContentView.swift, Launchpad_BackApp.swift, 新建 ThreeFingerDragCoordinator.swift.
编译验证. 仔细处理坐标和状态机, 确保四指捏合无回归.`, {
  label: 'G:三指拖动', phase: '阶段4: 三指拖动(G)', effort: 'high', schema: SCHEMA,
})

// ============================================================
phase('验证')

const verify = await agent(`${CTX}

【综合验证】
1. 编译: cd /Users/mac/Downloads/Launchpad_Back && xcodebuild -project Launchpad_Back.xcodeproj -scheme Launchpad_Back -configuration Release -derivedDataPath /tmp/lh_build build 2>&1 | grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED". 有error就修.
2. 逐项核对(读代码):
   ①触发角 ②垂直滚动开关 ③自定义名字 ④自定义来源 ⑤隐藏 ⑥隐藏管理 ⑦右键菜单结构 ⑧卸载 ⑨三指拖动 ⑩语言重开按钮
3. 检查冲突: 共享文件(SettingsView/ContentView/AppIconView/Launchpad_BackApp/LaunchpadViewModel)改动有无互相破坏
4. 回归: 点击打开/空白退出/四指捏合/长按编辑 是否被破坏
5. 特别检查: AppIconView 新增 onRename/onUninstall 回调是否在 ContentView 接入(Agent E 标注的 TODO 是否被解决, 若没有需补上)
返回详细报告: 每项✓/✗, 编译结果, 修复的问题, 剩余风险.`, {
  label: '验证', phase: '验证', effort: 'high', schema: SCHEMA,
})

return { A: agentA, B: agentB, C: agentC, D: agentD, E: agentE, F: agentF, G: agentG, verify }
