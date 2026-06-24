---
name: module-subagent-coding
description: Use for code changes in this project. The main agent studies project/framework context and 项目工程实施经验.md first, reviews architecture and main logic, then decides whether to implement directly or delegate to a subagent based on scale, parallelism benefit, context cost, and risk isolation. The main agent writes or updates tests and performs verification; failed verification goes back to the subagent for correction.
---

# Module Subagent Coding

Use this skill for non-trivial code changes in this project.

## Experience Lookup First

Before planning or coding, read the top summary/catalog of:

```text
代码框架说明.md
项目工程实施经验.md
```

Then search/read the specific sections whose keywords match the target module, such as:

- `菜单栏`, `SwiftUI`, `MenuBarExtra`
- `计时状态机`, `BreakTimerEngine`, `休息统计`, `长休息`
- `锁屏`, `睡眠`, `systemAway`
- `设置页`, `UserDefaults`, `BreakSettings`
- `Xcode`, `xcodebuild`, `测试`

Both the main agent and the coding subagent must be told to use the relevant experience sections.

## Role Split

Main agent responsibilities:

1. Understand user intent and affected modules.
2. Read relevant source files and matching experience sections.
3. Review the project architecture and local code framework before implementation.
4. Decide and explicitly sanity-check architecture, state model, main logic, technical choices, module boundaries, complexity, and implementation cost.
5. Write or update tests and define expected behavior.
6. Decide whether to delegate implementation to a subagent or do it directly. Delegate when scale, parallelism, or risk isolation justify it; do the work directly for small, single-module, or context-heavy tasks.
7. Run verification and review the diff against the approved framework and main logic.
8. If verification fails, send the failure and required fix back to the subagent.
9. Update `项目工程实施经验.md` after a bug fix or repeated issue.

## Main-Agent Architecture Gate

Before any subagent writes code, the main agent must answer these checks:

- **Project fit**: Does the approach match the current app architecture, ownership boundaries, and existing patterns?
- **Code framework**: Which files own state, UI, services, persistence, and tests? Are responsibilities staying in the right layer?
- **Main logic**: What is the state flow or data flow? Which edge cases must be preserved?
- **Technical choice**: Is the chosen API/library/pattern the simplest one that fits the existing project?
- **Implementation cost**: Is the change scoped, testable, and worth its complexity? Is a smaller change enough?
- **Risk and validation**: What tests/build/manual checks will prove the behavior?

If any answer is unclear, the main agent must read more code or experience sections before delegating.

Coding subagent responsibilities:

1. Read the files and experience sections named by the main agent.
2. Implement only the scoped code change approved by the main agent.
3. Follow existing project patterns.
4. Do not change architecture, module boundaries, technical choices, or main logic unless the main agent explicitly revises the plan.
5. Return changed files, reasoning summary, and any risks.

## Delegation Prompt Shape

When delegating, include:

```text
Task:
<specific implementation task>

Relevant files:
- <file>

Experience sections to read first:
- <section title or keywords from 项目工程实施经验.md>

Constraints:
- Keep scope limited to <module>.
- Do not change unrelated behavior.
- Do not change the approved architecture, module boundary, main logic, or technical choice without asking.
- Follow existing patterns.

Acceptance:
- <tests or manual verification that must pass>
```

## Verification Loop

1. Main agent runs focused tests first.
2. Main agent runs broader build/test if the change touches shared state or app wiring.
3. If tests fail, do not patch randomly in the main agent unless the failure is a trivial test typo.
4. Send failure output and target behavior back to the coding subagent for correction.
5. Main agent re-runs verification and reviews the final diff.

## Code Commenting Standards

All code in this project must include Chinese comments for readability by the project owner.

### File Header

Every Swift file must start with a header comment block explaining:

```swift
//
//  FileName.swift
//  Eye Break
//
//  职责：<文件在框架中的角色，2-3 行>
//  依赖：<依赖的模块或服务>
//  被使用：<哪些文件使用本文件>
//
```

### Function Comments

Every function must have a Chinese comment before it explaining:

- **作用**：函数做什么
- **逻辑**：内部的主要逻辑步骤（不需要逐行解释，概括关键分支和流程即可）
- **参数/返回值**：如果参数名不足以说明意图，补充说明

```swift
/// 处理系统唤醒后的状态恢复。
///
/// 逻辑：
/// 1. 若唤醒后不在活跃时间，进入 inactive
/// 2. 工作中离开：根据 awayDuration 和 remainingSeconds 决定重置还是恢复
/// 3. 休息中离开：继续消耗休息倒计时，超时则完成休息
mutating func systemDidWakeOrUnlock() { ... }
```

### Inline Comments

Complex logic blocks should have brief Chinese inline comments:

```swift
// 午休时段暂停计时
if settings.lunchPauseEnabled && minute >= settings.lunchStartMinute && minute < settings.lunchEndMinute {
    return false
}
```

### Comment Principles

- **写清楚意图（Why），不是翻译代码（What）**
- 函数注释让用户能理解这个函数在整体流程中的作用
- 不逐行翻译 Swift 语法，概括逻辑分支即可
- 更新代码时同步更新注释

## Delegation Decision (Main Agent Judges)

The main agent decides whether to delegate to subagents based on its own assessment of:

- **Task scale**: How many files? How many lines of code? Multi-module or single-module?
- **Parallelism benefit**: Can work be split into independent pieces that run concurrently?
- **Context cost**: Would a subagent need to read the same files the main agent already read? If so, the main agent should just do it.
- **Risk isolation**: Is the change risky enough that independent verification by a separate agent adds value?

Typical cases where the main agent does NOT delegate:
- Single-line fixes, typos, documentation-only changes
- Tasks where the main agent already holds all relevant context
- Simple changes to a single file the main agent has already read

Typical cases where delegation makes sense:
- Multiple independent files need parallel changes
- Complex multi-step implementation with verification checkpoints
- The main agent wants adversarial review of its own work

The main agent should briefly state its delegation decision and reasoning before proceeding.
