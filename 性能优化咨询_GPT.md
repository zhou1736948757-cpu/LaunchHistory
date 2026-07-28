# LaunchHistory 三指拖动 CPU 性能优化咨询

## 项目背景
- **LaunchHistory**：macOS Launchpad 替代应用（Swift/SwiftUI/AppKit），fork 自开源项目，不上 App Store
- 全屏 borderless 窗口（.screenSaver 层级），SwiftUI 视图树
- 三指拖动基于私有 `MultitouchSupport.framework`（dlopen + MTRegisterContactFrameCallback），触控板每帧回调触点数据（约 125-250Hz）
- 性能问题：三指拖动时 CPU 峰值约 42%，平均 23.6%。空闲时 0.1%（正常）

## 已完成的排查实验（关键数据）

用 A/B 对比实验定位根因。每次实验都实测了 CPU（ps 采样，每0.3秒一次，12秒）。

### 实验1：节流 Multitouch 事件派发频率
- 改动：三指拖动 changed 事件每3帧才派发一次（125-250Hz → ~40-80Hz）
- 结果：峰值 42.4% → 46.0%（没降，反而略升）；平均 23.6% → 22.8%（几乎没变）
- **结论：Multitouch 回调频率不是主因**

### 实验2：跳过落点计算（findDropTargetByScreenLocation）
- 改动：三指拖动 changed 时跳过 `findDropTargetByScreenLocation` 和 `checkEdgeForPageChange`（只更新 location）
- 结果：峰值 42.4% → 42.1%（没降）；平均 23.6% → 17.9%（降约24%）
- **结论：落点计算占部分持续开销，但不是峰值主因**

### 实验3：跳过 location 更新（关键实验）
- 改动：三指拖动 changed 时**连 `floatingDragState.location` 都不更新**（changed 等于空操作，只保留 began/end）
- 结果：峰值 42.4% → **12.4%**；平均 23.6% → **5.7%**
- **结论锁定根因**：CPU 开销主因 = `floatingDragState.location` 每帧更新触发 SwiftUI 视图树重渲染

### 实验4：纯打开/关面板（不拖动）
- 结果：峰值 18.8%，平均 4.7%
- **结论**：打开面板本身开销小，峰值确实是三指拖动导致

## 根因确认

> **三指拖动 CPU 高的根因：每帧（125-250Hz）更新 `floatingDragState.location`（一个 `@State` CGPoint），触发整个 SwiftUI 视图树重渲染。**

视图树结构（ContentView.swift）：
```swift
GeometryReader { geometry in
    ZStack {
        LaunchpadBackgroundView().allowsHitTesting(false)        // 背景
        Rectangle().onTapGesture { handleEscapeKey() }            // 空白点击捕获层
        VStack {
            normalHeaderView / editingHeaderView                  // 搜索栏+按钮
            ZStack {                                             // 应用图标网格（LazyVGrid）
                ForEach(renderedPageIndices) { PageViewEditable(...) }
            }
            PageIndicatorView(...)                               // 页面指示器
        }
        if let folder = expandedFolder { FolderExpandedView(...) }  // 文件夹展开
        if let item = floatingDragState.item {
            floatingDragOverlay(item: item, location: floatingDragState.location, in: geometry)  // ← 浮动图标，读 location
        }
    }
}
```

`floatingDragState` 是 `@State`，包含：draggingItemId, item, **location**, startedInGrid, dropTargetId, dropTargetIndex。

问题：`floatingDragOverlay` 在主 ZStack 里读 `floatingDragState.location`，所以 location 每帧变化 → 整个 LaunchpadView（含图标网格 LazyVGrid）重渲染。

## 已尝试的优化方案及结果

### 方案A：location 更新节流到 60fps（16ms）
- 改动：updateThreeFingerDrag 里用 `CACurrentMediaTime()` 判断，距上次更新不足16ms 就跳过
- 结果：峰值 42.4% → 38.3%（降4点）；平均 23.6% → 18.7%（降约20%）
- **效果有限**：60fps 仍是每秒60次重渲染，对比诊断2的0次还是多

### 方案B：把 location 抽成独立 ObservableObject（失败，更糟）
- 思路：让浮动图标 overlay 独立观察 location，主网格视图树不随 location 变化重渲染
- 改动：
  - 从 `floatingDragState`（@State struct）移除 location 字段
  - 新建 `FloatingOverlayPosition: ObservableObject`，`@Published var location: CGPoint`
  - LaunchpadView 加 `@StateObject overlayPosition`
  - 所有 `floatingDragState.location = x` → `overlayPosition.location = x`
  - overlay 读 `overlayPosition.location`
- 结果：**CPU 飙到 100%**（峰值100.3%，平均50.5%）！比基线还差
- **失败原因分析**：
  - `@StateObject` 的 `@Published` 变化会通知所有观察该 ObservableObject 的视图重渲染
  - 关键：overlay 仍在主 ZStack 里，主视图 `LaunchpadView` 仍读 `overlayPosition.location` 传给 overlay —— **主视图还是依赖它，还是全量重渲染**
  - 且 `ObservableObject` 的通知机制比 `@State` 更重（对象级 willChange 发送），高频更新下开销更大
  - 真正隔离需要把 overlay 拆成完全独立的子视图，自己 `@ObservedObject`，主视图完全不碰 location —— 但工程改动大且易错

## 当前状态

- 已回退所有优化改动，回到稳定版（commit 2ec6891，tag v0.5-CPU优化前稳定版）
- 三指拖动功能正常，CPU 峰值 42%（只拖动那2秒），空闲 0.1%

## 关键约束

1. 浮动图标必须跟随鼠标（不能像诊断2那样完全不更新位置）
2. 不能破坏三指拖动功能、四指捏合、文件夹等其他已稳定功能
3. macOS SwiftUI（不是 iOS），全屏 borderless 窗口
4. 三指拖动通过 NotificationCenter 派发事件（MultitouchSupport C 回调 → 主线程 → 通知 → ContentView onReceive）

## 事件流（三指拖动 changed）
```
MultitouchSupport C 回调（后台线程，125-250Hz）
  → MultitouchGestureRecognizer.handleFrame → processThreeFingerFrame
  → emitThreeFingerEvent(.changed(location))  // 切主线程
  → ThreeFingerDragCoordinator.handle → postEvent → NotificationCenter.post
  → ContentView.onReceive(threeFingerDragUIEvent)
  → handleThreeFingerDragEvent(.change(loc))
  → updateThreeFingerDrag(loc)
  → floatingDragState.location = loc        // ← @State 变化，触发重渲染
  → checkEdgeForPageChange + findDropTargetByScreenLocation
  → floatingDragState.dropTargetId/Index 更新
```

## 想请 GPT 思考的问题

1. SwiftUI macOS 上，如何让一个高频变化的 CGPoint 只重画一个小的 overlay 子视图，而不触发整个视图树（含 LazyVGrid 图标网格）重渲染？具体哪种机制最干净（独立子视图 + @ObservedObject？GeometryPreferenceKey？Canvas？CATimer+CALayer 绕过 SwiftUI？）

2. 方案B（独立 ObservableObject）为什么会更糟（100% CPU）？是不是我的实现方式错了——overlay 仍在主视图树里读 location 导致主视图仍全量重渲染？正确的隔离姿势是什么？

3. 是否应该放弃 SwiftUI 的 overlay，改用 AppKit 的 NSView/NSImageView 跟随鼠标（CALayer 直接设 position，不经过 SwiftUI 渲染管线）？这种"SwiftUI 主视图 + AppKit 浮动层"的混合方案在 macOS 上可行吗？

4. 或者用 `Canvas` 视图绘制浮动图标（Canvas 重绘开销是否比 SwiftUI View 树重渲染小）？

5. 当前 42% 峰值（仅拖动2秒，空闲0.1%）从产品角度是否可接受？还是必须优化？

## 关键文件
- `ContentView.swift`：主视图，floatingDragState（@State）、floatingDragOverlay、updateThreeFingerDrag
- `MultitouchGestureRecognizer.swift`：三指拖动检测，emitThreeFingerEvent
- `ThreeFingerDragCoordinator.swift`：事件派发（NotificationCenter）

## 回滚点
- git tag `v0.5-CPU优化前稳定版`（commit 2ec6891）
- 独立备份目录 `~/Downloads/LaunchHistory_backup_CPU优化前_20260728/`
