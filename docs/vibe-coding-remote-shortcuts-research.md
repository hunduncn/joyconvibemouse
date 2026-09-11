# Vibe Coding 遥控器按键调研与优化建议

> 调研日期：2026-09-01  
> 范围：macOS 上的 ChatGPT/Codex 桌面应用、Codex CLI、Claude Code 终端交互，以及通用 macOS 操作  
> 证据标准：只使用 OpenAI、Anthropic、Apple 的官方文档及 OpenAI 官方源码；建议部分与已证实行为分开

## 结论

对“不坐在电脑前，用 Joy-Con 驱动 Vibe Coding”而言，真正高频的不是完整键盘，而是五类闭环操作：

1. **输入并提交：**语音输入、回车、删除、换行；
2. **处理 Agent 停顿：**批准、拒绝、取消/中断；
3. **在选择器中导航：**四方向、Tab、回车、Esc；
4. **阅读和切换：**滚动、切换应用、切换任务/面板；
5. **复用内容：**复制、粘贴、命令历史、斜杠命令。

当前 Joy-Con 映射已经覆盖了体感、回车、Esc、Tab、删除、鼠标、滚动和应用切换，主干是合理的。最明显的缺口不是再增加一个普通字符键，而是：

- 摇杆纵向目前只滚动，无法在终端菜单/权限对话框中发出 `↑/↓`；
- 没有“复制”“粘贴”“插入换行”等组合动作；
- Codex 桌面、Codex CLI 和 Claude Code 的语音、复制、审批键并不相同，单一全局映射无法同时做到最优；
- Codex CLI 的命令审批主要使用 `y/a/p/d/n/c`，单有 Enter/Esc 只能覆盖一部分交互；
- Claude Code 原生按住 Space 录音，而当前项目的普通按键动作只发送瞬时 key tap，无法表达“按住 Space 直到松键”。

推荐的产品方向是：**保留现有主层，再增加一个按住式导航/命令副层，并最终支持按前台应用自动切换配置。**不要把有限的主层按钮永久换成低频复杂快捷键。

## “Agent Panels”的边界

官方资料中没有一个跨 OpenAI/Anthropic、名称就叫 “Agent Panels” 的统一产品或快捷键规范。本文把它理解为以下界面的统称：

- Codex 桌面应用的聊天、终端、Review、Browser、Activity 等面板；
- Codex CLI 和 Claude Code 的权限对话框、选择器、任务列表、diff/transcript 等终端界面。

因此，下文不会把某个客户端的按键推测成其他客户端也支持。

## 当前 Joy-Con 实际映射

项目目前使用“单按 + 按住 SL 后”成对绑定；默认值为：

| Joy-Con 操作 | 单按 | 按住 SL 后 |
| --- | --- | --- |
| R | Fn | 同单按 |
| SR | Return/Enter | Shift+Enter 换行但不发送 |
| A | Esc | Control+C 强制中断 |
| Y | 鼠标左键 | 同单按 |
| B | 鼠标右键 | 同单按 |
| X | 向后删除，可长按连删 | 同单按 |
| + | `Command-Tab` 切换应用 | 同单按 |
| Home | 打开状态面板 | 轮换输入 `/ @ $ !` |
| 摇杆按下 | Tab | Shift+Tab |
| 摇杆上下 | 滚动 | `↑/↓` |
| 摇杆左右 | `←/→` | `←/→` |

ZR 仍是独立体感离合键；按住 ZR + SL 进入精准低灵敏度模式，这个组合优先于 SL 按键层。所有可配置实体键的两种动作都来自同一个 [`RemoteButtonBinding`](../Sources/JoyConVibeCore/JoyConTypes.swift)，并在设置面板同一行中绑定和恢复默认值。

## 三种客户端的已证实操作

### 1. ChatGPT/Codex 桌面应用（macOS）

OpenAI 的桌面应用快捷键表明确记录：

- 审批弹窗中，`Enter` 批准，`Esc` 拒绝；
- 输入框为空时，`↑` 恢复上一条 composer prompt；
- `Control-Shift-D` 开始听写，`Control-Shift-V` 开始 Voice；
- `Command-Option-A` 跳到下一个需要注意的 Codex 任务；
- `Command-J` 切换底部面板，`Control-反引号`切换终端；
- `Command-Option-B` 切换 Review 面板，`Command-Shift-B` 切换 Browser 面板；
- `Command-K` 或 `Command-Shift-P` 打开命令菜单，`Command-P` 搜索文件；
- `Control-Tab` / `Control-Shift-Tab` 可切换下一/上一聊天或标签页。

来源：[OpenAI：ChatGPT desktop app commands](https://learn.chatgpt.com/docs/reference/commands#keyboard-shortcuts)

对遥控器而言，最高价值的是 `Enter`、`Esc`、`↑`、滚动以及“下一个需要注意的任务”。面板快捷键很多，但不适合各占一个物理键；应作为副层动作或可选宏。

### 2. Codex CLI

OpenAI 官方 CLI 文档和源码当前明确区分：

- `Enter` 提交当前输入；
- Agent 正在工作时，`Tab` 把 follow-up、斜杠命令或 shell 命令排到下一轮，`Enter` 则把新指令注入当前 turn；
- `Esc` 中断当前 turn；
- `↑/↓` 恢复输入历史，`Control-R` 搜索 prompt 历史；
- `Control-O` 或 `/copy` 复制最近完成的 Codex 输出；
- `/` 打开命令列表，`@` 搜索并提及工作区文件，行首 `!` 运行本地 shell 命令；
- `/permissions`、`/diff`、`/review`、`/status`、`/ps`、`/stop`、`/compact` 是常用的会话管理入口。

来源：[OpenAI：Codex CLI reference，Interactive shortcuts 与 slash commands](https://learn.chatgpt.com/docs/developer-commands?surface=cli#interactive-shortcuts)

公开文档没有完整列出审批面板的字母键；OpenAI 官方源码在本次调研固定 commit `2e5ee418` 中给出的默认审批键是：

- `y`：批准一次；
- `a`：本次会话批准；
- `p`：按命令前缀批准；
- `d`：拒绝；
- `Esc` 或 `n`：decline；
- `c`：取消审批面板。

同一默认 keymap 还确认：选择列表使用四方向、`Enter` 接受、`Esc` 取消；composer 默认 `Enter` 提交、`Tab` 排队、`Esc` 中断。[OpenAI 官方源码：Codex TUI 默认 keymap](https://github.com/openai/codex/blob/2e5ee418ad6bef8b418ba1a809cfa53a56ae4aee/codex-rs/tui/src/keymap.rs#L1410-L1687)

这意味着：面向 Codex CLI 的完整审批遥控不能只依赖桌面应用的“Enter=批准”。如果希望遥控器能选择“仅这次允许”和“本会话允许”，以后需要增加 `y`、`a` 等语义宏，或为 Codex CLI 单设 profile。

### 3. Claude Code（终端）

Anthropic 的交互模式文档明确记录：

- `Enter` 提交；Claude 工作时按 Enter 会把消息排队；
- `Esc` 中断响应/工具调用、关闭对话框，在权限提示中等同于无评论的 No；`Control-C` 也可中断，空闲时第一次清空输入、第二次退出；
- `←/→` 在权限对话框和菜单的 tab 之间切换；`↑/↓` 移动输入光标或浏览命令历史；
- `Tab` 接受自动补全；在大多数权限提示中，焦点位于 Yes/No 时会打开评论字段；
- `Shift-Tab` 轮换权限模式，并可在权限提示中选择“本会话允许”的选项；
- `Control-R` 搜索历史；
- 通用换行可用 `Control-J`，部分终端支持 `Shift-Enter` 或 `Option-Enter`；
- 启用 Claude Code Voice 后，按住 Space 录音；运行 `/voice tap` 后可改成点按切换；
- `Control-O` 是 transcript viewer，不是复制最近回答。

来源：[Anthropic：Claude Code interactive mode](https://code.claude.com/docs/en/interactive-mode#keyboard-shortcuts)

Claude Code 的高价值斜杠命令包括：

- `/permissions`：管理权限；
- `/tasks`：查看后台 shell 和 subagent；
- `/status`：查看会话状态；
- `/diff`：查看变更；
- `/review` / `/code-review`：代码审查；
- `/compact`：压缩上下文；
- `/copy`：复制最近回答；
- `/voice hold|tap|off`：设置语音模式。

来源：[Anthropic：Claude Code commands](https://code.claude.com/docs/en/commands#commands-across-a-typical-workflow)

Claude Code 的权限 UI 尤其依赖方向键、Tab、Enter、Esc；文档说明 Yes/No 可附评论，`Enter` 提交，`Esc` 拒绝。[Anthropic：Configure permissions](https://code.claude.com/docs/en/permissions#add-a-comment-when-you-answer-a-permission-prompt)

## macOS 通用操作

Apple 官方文档确认：

- `Command-C`、`Command-V` 是通用复制、粘贴；
- `Command-Tab` 切换最近使用的应用；
- 开启 Keyboard navigation 后，`Tab` 前移焦点、`Shift-Tab` 后移焦点；
- 系统听写快捷键可以在 Keyboard 设置中自定义。可用麦克风键或自定义组合键；选择“按 Fn 两次”时需要双击 Fn，并非所有 Mac 都把单次 Fn 当听写。

来源：[Apple：Mac keyboard shortcuts](https://support.apple.com/zh-cn/102650)、[Apple：Keyboard settings](https://support.apple.com/en-gb/guide/mac-help/kbdm162/mac)、[Apple：Dictate messages and documents](https://support.apple.com/en-gb/guide/mac-help/mh40584/mac)

因此当前 `R = 单次 Fn` 是用户本机已验证的配置，不应在产品说明中宣称为所有 Mac 的固定听写键。更稳妥的产品接口应叫“系统听写”并允许设置具体组合键。

## 跨客户端优先级

| 优先级 | 能力 | 原因 |
| --- | --- | --- |
| P0 | Enter | 发送 prompt、确认选择；Codex 桌面可直接批准 |
| P0 | Esc | 跨客户端最接近“拒绝/关闭/中断”的统一键 |
| P0 | 四方向 | 权限、菜单、diff、历史、选择器都依赖；当前缺纵向方向模式 |
| P0 | Tab | 自动补全、Codex CLI 排队、Claude 权限评论、macOS 焦点导航 |
| P0 | 滚动 + 左/右键 | 阅读长回复与处理 UI，不应被键盘功能挤掉 |
| P1 | 语音输入 | 远距离 Vibe Coding 的主要文字入口，但不同客户端触发方式不同 |
| P1 | 删除/长按连删 | 修正听写和 prompt |
| P1 | 切换应用/任务 | 在 Agent、终端和预览之间来回 |
| P1 | 复制、粘贴 | 复用报错、代码和回答；当前缺组合宏 |
| P1 | 插入换行 | 输入结构化 prompt；Claude Code 可用 `Control-J` |
| P2 | 历史搜索、复制最近回答、review/status 等 | 很有用，但客户端快捷键冲突，适合 profile 或文本宏 |

## 建议的映射优化

### 第一阶段：不破坏现有手感

主层继续使用当前映射。只增加一个“按住 Home 的副层”：

| 按住 Home 后 | 建议动作 |
| --- | --- |
| 摇杆四方向 | 真正的 `↑/↓/←/→`，用于菜单、权限、历史和选择器 |
| Y | 复制 `Command-C` |
| B | 粘贴 `Command-V` |
| X | 插入换行；终端 profile 可发 `Control-J` |
| A | 保持 Esc，避免紧急时还要记另一层 |
| SR | 保持 Enter |

Home 短按仍打开状态面板；只有按住进入副层。这样主层摇杆仍可顺滑滚长回复，同时解决终端 UI 缺 `↑/↓` 的问题。

### 第二阶段：增加“语义动作”，不要只增加原始按键

设置面板建议新增这些可选动作：

- `复制`（`Command-C`）与 `粘贴`（`Command-V`）；
- `插入换行`，根据 profile 发送 `Control-J` 或目标客户端配置的 Shift-Enter；
- `Codex 桌面听写`（`Control-Shift-D`）；
- `Claude Voice 按住说话`（物理按下时 Space down，松开时 Space up）；
- `下一个需处理的 Codex 任务`（`Command-Option-A`）；
- `Codex CLI 批准一次/本会话批准/拒绝`（`y/a/d`）；
- `输入文本并可选提交`，用于 `/permissions`、`/tasks`、`/diff`、`/review`、`/copy` 等命令。

语义动作比让用户自己拼三个修饰键更适合遥控场景，也能在 UI 中显示清楚的人类语言。

### 第三阶段：按前台应用自动切换 profile

建议至少提供：

1. **通用/Codex 桌面 profile：**R 为系统听写或 `Control-Shift-D`；Enter/Esc 直接审批；提供“下一个需处理任务”。
2. **Codex CLI profile：**保留 Enter/Esc/Tab，增加 `y/a/d` 审批动作、`Control-O` 复制最近回答、`Control-J` 换行。
3. **Claude Code profile：**R 可设为按住 Space 的原生 Voice；保留方向、Tab、Enter、Esc；复制最近回答用 `/copy` 宏而不是 `Control-O`。

这是必要的，不只是锦上添花：`Control-O` 在 Codex CLI 是复制最近输出，在 Claude Code 却是 transcript viewer；同一物理键无法用一个全局快捷键同时表达正确意图。

## 不建议的调整

- 不要拿掉 Esc。它是三类环境中最接近统一“停止/拒绝/返回”的安全键。
- 不要让摇杆永久只发四方向而失去滚动；阅读 Agent 长输出仍是高频需求。
- 不要把 `Control-C` 设成唯一中断键。它在不同状态可能同时具有清空输入或退出含义，Esc 更稳妥。
- 不要把单次 Fn 宣传为通用 macOS 听写规范；应保留用户自定义或提供明确的组合键动作。
- 不要给 `/review`、`/status` 等每个命令各占主层物理键；用副层、命令菜单或文本宏承载。

## 推荐决策

近期最值得实现的三项功能依次是：

1. **Home 按住副层 + 摇杆完整四方向；**
2. **复制、粘贴、插入换行和“按住键直到松开”四类动作；**
3. **按前台应用自动切换 profile，并提供 Codex Desktop / Codex CLI / Claude Code 三个预设。**

当前物理布局本身不需要推倒重来：`ZR 体感 + SR 回车 + R 语音 + A Esc + 摇杆/Tab + 鼠标键`已经是很好的主层。优化重点应从“再塞几个键”转向“副层、语义宏和应用上下文”。
