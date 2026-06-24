---
name: engineering-experience-log
description: Record project engineering lessons in 项目工程实施经验.md. Use whenever Codex fixes a bug, modifies an existing problem, addresses repeated implementation issues, or the user asks to summarize past engineering problem experience; update an existing similar section instead of duplicating it, and record the update time.
---

# Engineering Experience Log

Use this skill after or during bug fixes and corrective changes in this project.

## Required Output File

Write to the repository root file:

```text
项目工程实施经验.md
```

Create it if missing.

## Before Editing Code

Before changing code for a bug fix or existing behavior change:

1. Read the `## 概要目录` section in `项目工程实施经验.md`.
2. Identify the affected module keywords, such as `菜单栏`, `SwiftUI`, `计时状态机`, `休息统计`, `长休息`, `锁屏`, `睡眠`, `UserDefaults`, `设置页`, `测试`.
3. Search `项目工程实施经验.md` with those keywords.
4. Read any matching sections before editing implementation or tests.
5. Apply the relevant prevention rules while designing the change.

## Workflow

1. Identify the engineering lesson from the current bug or modification.
2. Search `项目工程实施经验.md` for a same or similar topic by section title and keywords.
3. If a matching section exists, update that section instead of creating a duplicate.
4. If no matching section exists, add a new section.
5. Record the latest update time in the section using local time.
6. Include concise, reusable engineering guidance, not a chat transcript.
7. Add or update `关键词：...` so future agents can find the lesson before coding.
8. Update `## 概要目录` so it briefly lists the section, keywords, and when to read it.

## Section Format

Use this shape for each section:

```markdown
## <problem category>

更新时间：YYYY-MM-DD HH:mm:ss CST

关键词：关键词1, 关键词2, 关键词3

问题：
<what went wrong or what risk appeared>

工程经验：
- <stable lesson>
- <implementation rule or review point>

验证：
- <test/build/manual check used, if applicable>
```

## Catalog Format

Maintain a top-level `## 概要目录` near the top of `项目工程实施经验.md`.

Each row should be short:

```markdown
| Section | Keywords | Read When |
| --- | --- | --- |
| [section title](#anchor) | keyword1, keyword2 | before changing ... |
```

The catalog is for quick context expansion: read it first, then load only the detailed sections that match the current module.

## Merge Rules

- Treat issues as similar when the root cause, affected subsystem, or prevention rule overlaps.
- Prefer improving the existing section title and bullets over adding another nearby section.
- Keep sections short; add only details that would help future implementation.
- Preserve older useful lessons, but replace stale wording when the new fix clarifies the rule.

## Trigger Examples

- User says “修 bug”, “修改这个问题”, “这个又错了”, “总结过往工程问题经验”.
- Codex discovers a regression or unexpected behavior while implementing.
- A test is added to prevent a repeated timing, state, persistence, UI, or build issue.
