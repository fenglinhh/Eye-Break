# Eye Break（每日休息）需求文档

> 基于当前代码 `codex/daily-break-mvp` 分支的已实现功能编写。本文档描述的是代码实际行为，不是目标规格。

---

## 1. 产品概述

### 1.1 定位

macOS 菜单栏应用。无 Dock 图标，以 `NSApplication.ActivationPolicy.accessory` 模式运行。

### 1.2 核心功能

定时提醒用户休息眼睛。默认每工作 20 分钟提醒一次、休息 20 秒（短休息）。可选启用休息周期，完成 N 次短休息后触发一次长休息。

---

## 2. 菜单栏

### 2.1 菜单栏图标

| 状态 | 展示内容 |
|---|---|
| 菜单栏倒计时开启 | 当前阶段对应的时间文字（等宽数字） |
| 菜单栏倒计时关闭 | 眼睛图标（`eye` SF Symbol） |

### 2.2 弹出窗口（MenuBarView）

宽度 260pt，由上至下包含：

**状态区**
- 状态行（headline 字体）：根据当前阶段动态显示文案
- 今日统计（caption 字体）：`短休息 X 次 · 长休息 Y 次`
- 下次休息类型提示（仅休息周期开启时显示）

**操作按钮**
| 按钮 | 显示条件 | 行为 |
|---|---|---|
| 暂停 | 非暂停状态下 | 暂停计时，保留剩余时间 |
| 恢复计时 | 暂停状态下 | 恢复到暂停前的阶段和剩余时间 |
| 立即休息 | 始终可用 | 立即开始短休息，不触发前置通知 |
| 重置 | 非暂停状态下，且处于 working/preBreak/postponed | 重新开始当前工作周期 |
| 打开设置 | 始终可用 | 关闭菜单窗口，打开设置面板 |
| 退出 Daily Break | 始终可用 | 终止应用 |

**Toast 消息区**
- 跳过休息后，弹出 toast 提示（3 秒自动消失）

**状态行文案**

| 阶段 | 显示文案 |
|---|---|
| inactive | `已暂停，HH:MM 开始`（有下次开始时间时）<br>`未在执行时间`（无下次开始时间时） |
| working | `距离休息还有 MM:SS` |
| preBreak | `N 秒后休息` |
| resting(.short) | `短休息中` |
| resting(.long) | `长休息中` |
| paused | `已暂停 MM:SS · 剩余 MM:SS` |
| systemAway | `锁屏或睡眠暂停中` |
| postponed | `已延后 · MM:SS 后提醒` |

**菜单栏标题文案（倒计时模式下）**

| 阶段 | 显示 |
|---|---|
| inactive | `休息` |
| paused | `暂停 MM:SS` |
| preBreak | `Ns` |
| resting | `休息 MM:SS` |
| 其他 | `MM:SS` |

---

## 3. 阶段状态机

### 3.1 阶段定义

```
inactive          — 不在活跃时间范围内
working           — 正常工作计时
preBreak          — 剩余 ≤ 30 秒，即将进入休息
resting(.short)   — 短休息中
resting(.long)    — 长休息中
paused            — 用户手动暂停
systemAway        — 系统睡眠/锁屏/会话切换
postponed         — 用户延后提醒
```

### 3.2 状态转换

```
inactive ←→ working → preBreak → resting(.short/.long) → working
                 ↑              ↑                          ↑
                 └── postponed ──┘                          │
                 └──────────── skip ────────────────────────┘
```

| 转换 | 触发条件 |
|---|---|
| inactive → working | 当前时间进入活跃时间范围 |
| working → preBreak | 工作倒计时 ≤ 30 秒 |
| working → inactive | 当前时间离开活跃时间范围 |
| preBreak → resting | 倒计时归零 |
| resting → working | 休息倒计时归零 |
| → paused | 用户点击暂停（working/preBreak/resting/postponed 均可） |
| paused → 原阶段 | 用户点击恢复，还原剩余时间和阶段 |
| → systemAway | 系统睡眠/锁屏/会话切换（需设置中开启 "锁屏时暂停计时"） |
| systemAway → 原阶段 | 系统唤醒/解锁，还原剩余时间和阶段；若离开活跃时间则 → inactive |
| → postponed | 用户在 preBreak/working/resting 中延后（+1 分钟起） |
| postponed → preBreak | 延后倒计时 ≤ 30 秒 |

### 3.3 跳过休息

- 在 working / preBreak / resting / postponed 均可跳过
- 跳过时 `consecutiveSkips += 1`，进入下一个工作周期
- 完成休息时 `consecutiveSkips` 重置为 0
- Toast 消息按跳过次数分级：

| 连续跳过次数 | 消息文案 |
|---|---|
| 0–1 | `已跳过本次休息` |
| 2 | `你今天已经跳过 2 次休息了` |
| 3–4 | `建议找个时间休息一下` |
| 5+ | `你已经连续工作较长时间了` |

### 3.4 休息周期

- **关闭**：每次均为短休息
- **开启**：每完成 `长休息触发频率` 次短休息后，下一次触发长休息
  - 默认：每 3 次短休息后触发 1 次长休息

---

## 4. 设置项

设置页面使用 macOS 原生 `.formStyle(.grouped)` 布局，窗口 520×680pt。修改后底部出现保存/撤销操作栏。

### 4.1 通用设置

| 设置项 | 控件 | 默认值 | 说明 |
|---|---|---|---|
| 开机自动启动 | Toggle | 关闭 | 通过 SMAppService.mainApp 注册/注销登录项 |
| 菜单栏显示倒计时 | Toggle | 开启 | 菜单栏图标显示倒计时文字而非眼睛图标 |

### 4.2 时间安排

| 设置项 | 控件 | 默认值 | 说明 |
|---|---|---|---|
| 工作时长 | TextField（圆角边框）+ "分钟"标签 | 20 分钟 | 输入正整数分钟数 |
| 重复 | Picker（menu 样式） | 每天 | 选项：每天 / 周一至周五 / 自定义 |
| 执行日期 | 7 个 Toggle（周一至周日） | 全选 | 仅 "自定义" 时显示，缩进排版 |
| 开始时间 | DatePicker（.stepperField，仅时分） | 09:00 | 非 "每天" 时显示 |
| 结束时间 | DatePicker（.stepperField，仅时分） | 18:00 | 非 "每天" 时显示 |
| 午休暂停 | Toggle | 开启 | 午休时段暂停计时 |
| 午休开始 | DatePicker（.stepperField，仅时分） | 12:00 | 仅午休暂停开启时显示 |
| 午休结束 | DatePicker（.stepperField，仅时分） | 14:00 | 仅午休暂停开启时显示 |

**活跃时间判定逻辑**（在 `BreakTimerEngine.isActiveTime` 中）：
1. 每天模式：始终活跃
2. 周一至周五 / 自定义：当前时间分钟数在 `[activeStartMinute, activeEndMinute)` 范围内
3. 若午休暂停开启：`[lunchStartMinute, lunchEndMinute)` 范围内为不活跃
4. 自定义模式还需当前 weekday 在 `customActiveWeekdays` 中

超出活跃时间时进入 inactive 阶段，并计算 `nextActiveStart`（向前搜索最多 14 天）。

### 4.3 休息周期

| 设置项 | 控件 | 默认值 | 说明 |
|---|---|---|---|
| 短休息时长 | Picker | 20 秒 | 选项：20 秒 / 30 秒 / 1 分钟 / 2 分钟 |
| 休息周期 | Toggle | 关闭 | 开启后显示长休息配置 |
| 长休息时长 | Picker | 3 分钟 | 仅休息周期开启时显示。选项：3 / 5 / 10 分钟 |
| 长休息触发频率 | Picker | 3 | 仅休息周期开启时显示。完成 N 次短休息后触发长休息。选项：2 / 3 / 4 / 5 |

### 4.4 休息界面

| 设置项 | 控件 | 默认值 | 说明 |
|---|---|---|---|
| 蒙层强度 | Picker | 中度 | 选项：轻度(0.72) / 中度(0.84) / 强度(0.93)，控制黑色蒙层不透明度 |
| 动画效果 | Toggle | 开启 | 休息界面主屏幕显示呼吸动画 Circle |
| 显示健康建议 | Toggle | 开启 | 休息界面显示随机健康建议文字 |
| 允许跳过休息 | Toggle | 开启 | 休息界面显示 "跳过" 按钮 |

### 4.5 通知设置

| 设置项 | 控件 | 默认值 | 说明 |
|---|---|---|---|
| 提前 30 秒提醒 | Toggle | 开启 | 倒计时 ≤ 30 秒时发送本地通知 |

### 4.6 保存 / 撤销

进入设置页时捕获当前设置的快照作为基线。任何设置项修改后，底部滑入操作栏：
- **撤销**：恢复所有设置项到快照值，显示 toast "已取消修改"，2.5 秒后消失
- **保存**：更新快照为当前值，操作栏隐藏（实际持久化已由 `didSet` 自动完成）

---

## 5. 休息蒙层

### 5.1 窗口配置

- 每个屏幕创建一个全屏 `NSWindow`
- `window.level = .screenSaver`（覆盖所有常规窗口）
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`
- 无边框（`.borderless`），背景透明
- 窗口内容为 SwiftUI 的 `RestOverlayView`

### 5.2 主屏幕界面

居中纵向排列：
1. 呼吸动画 Circle（青色半透明，2.4 秒缩放循环，仅动画效果开启时显示）
2. 休息标题："短休息时间" / "长休息时间"（36pt）
3. 倒计时数字（56pt，等宽数字，`MM:SS` 格式）
4. 进度条（线性，360pt 宽）
5. 健康建议文字（仅健康建议开启时显示）
6. 跳过按钮（仅允许跳过休息时可用，点击后立即结束休息进入下一工作周期）

### 5.3 副屏幕界面

简化显示：标题 "当前处于休息状态" + 剩余时间。

---

## 6. 系统集成

### 6.1 通知

- 启动时请求通知授权
- 倒计时 ≤ 30 秒时发送本地通知："30 秒后开始休息" / "可以先保存一下当前工作"
- 通知标识符：`daily-break.pre-break`（相同 ID 会覆盖前一条）

### 6.2 系统活动监听

通过 `NSWorkspace` 通知中心和 `DistributedNotificationCenter` 监听以下事件：

| 事件 | 行为 |
|---|---|
| `willSleep` / `screensDidSleep` / `sessionDidResignActive` | 进入 systemAway |
| `screenIsLocked`（分布式通知） | 进入 systemAway |
| `didWake` / `screensDidWake` / `sessionDidBecomeActive` | 从 systemAway 恢复 |
| `screenIsUnlocked`（分布式通知） | 从 systemAway 恢复 |

systemAway 时暂停计时，恢复时还原剩余时间。若唤醒后已离开活跃时间范围，则进入 inactive。

### 6.3 登录自启

通过 `SMAppService.mainApp.register()/unregister()` 控制。

---

## 7. 数据持久化

### 7.1 存储方式

`DailyBreakStore` 使用 `UserDefaults` 存储，JSON 编码：

| 键 | 内容 |
|---|---|
| `dailyBreak.settings` | `BreakSettings` 完整序列化 |
| `dailyBreak.stats` | `BreakStats`（按天 key 区分，跨天自动重置） |

### 7.2 统计数据结构

```
BreakStats {
    dayKey: "2026-6-23"    // 日期标识，用于跨天检测
    shortBreaks: Int        // 当日短休息完成次数
    longBreaks: Int         // 当日长休息完成次数
    consecutiveSkips: Int   // 连续跳过次数（跨天不重置，完成一次休息后归零）
}
```

### 7.3 设置解码

所有字段使用 `decodeIfPresent`，缺失键回退到 `BreakSettings.defaults`，确保旧版本数据向前兼容。

---

## 8. 默认配置（出厂值）

| 参数 | 默认值 |
|---|---|
| 工作时长 | 20 分钟 |
| 短休息时长 | 20 秒 |
| 长休息时长 | 3 分钟 |
| 长休息触发频率 | 每 3 次短休息 |
| 休息周期 | 关闭 |
| 重复 | 每天 |
| 活跃开始时间 | 09:00 |
| 活跃结束时间 | 18:00 |
| 午休暂停 | 开启（12:00–14:00） |
| 提前 30 秒通知 | 开启 |
| 菜单栏倒计时 | 开启 |
| 开机自启 | 关闭 |
| 蒙层强度 | 中度（opacity 0.84） |
| 动画效果 | 开启 |
| 健康建议 | 开启 |
| 允许跳过 | 开启 |
| 锁屏暂停 | 开启 |
| 长时间离开后重置 | 开启 |
