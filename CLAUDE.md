# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 构建与测试

```bash
# 构建
xcodebuild -project "Eye Break.xcodeproj" -scheme "Eye Break" -configuration Debug build

# 运行所有测试
xcodebuild -project "Eye Break.xcodeproj" -scheme "Eye Break" -configuration Debug test

# 运行单个测试
xcodebuild -project "Eye Break.xcodeproj" -scheme "Eye Break" -configuration Debug test -only-testing "Eye BreakTests/BreakTimerEngineTests/testName"
```

## 架构概览

这是一个 macOS 菜单栏应用（menu bar extra），用于定时提醒休息眼睛。应用以 `NSApplication.ActivationPolicy.accessory` 方式运行 — 无 Dock 图标，仅菜单栏图标 + 弹出窗口 + 设置面板。

### 核心分层

1. **状态机** — `BreakTimerEngine`（纯值类型 struct，无 SwiftUI 依赖）：管理所有阶段转换（`working → preBreak → resting → working`）。通过构造函数注入 `now: () -> Date` 和 `Calendar` 实现完全测试隔离，不依赖真实时钟。

2. **数据模型** — `DailyBreakModel`（`@MainActor ObservableObject`）：应用中唯一的 ViewModel/ObservableObject。持有 `BreakTimerEngine` 实例、所有 service 实例，并通过 1 秒 Timer 驱动 `engine.tick()` → `syncFromEngine()` 循环。所有 View 只与 `DailyBreakModel` 交互，不直接接触 engine。

3. **持久化** — `DailyBreakStore`：将 `BreakSettings` 和 `BreakStats` 编码为 JSON 存入 `UserDefaults`。

4. **服务层** — `AppServices.swift` 中的四个类：
   - `NotificationService`：发送 "30 秒后休息" 的本地通知
   - `LaunchAtLoginService`：通过 `SMAppService.mainApp` 管理登录自启
   - `SystemActivityMonitor`：监听睡眠、锁屏、会话切换等系统事件
   - `RestOverlayController`：每个屏幕创建一个全屏 `NSWindow`（level: `.screenSaver`）的休息蒙层

5. **View 层**：
   - `MenuBarView`：菜单栏弹出窗口，显示状态和操作按钮
   - `SettingsView`：设置表单（`.formStyle(.grouped)`）
   - `RestOverlayView`：全屏休息界面，包含呼吸动画 Circle 和倒计时

### 阶段状态机 (`BreakPhase`)

```
inactive ←→ working → preBreak → resting(.short/.long) → working
                 ↑              ↑                          ↑
                 └── postponed ──┘                          │
                 └──────────── skip ────────────────────────┘
paused: 可从 working/preBreak/resting/postponed 进入，恢复时回到原阶段
systemAway: 可从 working/preBreak/resting/postponed 进入（锁屏/睡眠），唤醒后恢复
```

- `preBreak` 在倒计时 ≤ 30 秒时触发，可发出前置通知
- `postponed` 延迟提醒（默认 +1 分钟），超时后重新回到 preBreak
- `paused` 冻结剩余时间；`systemAway` 同样冻结但由系统事件驱动
- 跳过休息会增加 `consecutiveSkips` 计数器，影响 toast 消息文案
- `BreakTimerEngine.upcomingBreakKind` 根据 `breakCycleEnabled` 和已完成短休息次数决定下次为短休息还是长休息

### 测试

`BreakTimerEngineTests` 使用 `TestClock`（可变 value type）注入日期，实现纯逻辑的确定性测试。测试覆盖：阶段转换、暂停/恢复、跳过、系统离场/返回、活跃时间段边界、休息周期切换。

### UI 开发原则

- **优先使用 Apple 原生组件**：时间选择用 `DatePicker`（`displayedComponents: .hourAndMinute`），选项用 `Picker` + `.menu` 或 `.segmented` 样式，数值输入用 `TextField` + `.roundedBorder` 样式。避免自定义实现已有系统控件覆盖的场景。
- 表单使用 `.formStyle(.grouped)`——这是 macOS Settings 窗口的标准样式。
