# GitHub Launch Notes

这份文档是给 `SubMax` 发布到 GitHub 时直接复用的。

## Repository Name

推荐直接用：

`SubMax`

## Repository Description

可以直接用这一句作为 GitHub 仓库描述：

`A native macOS app for subscription health checks, proxy node speed tests, packet loss monitoring, exit IP detection, and GPT / Gemini / Claude / Netflix reachability checks.`

如果你想更偏中文，也可以用：

`一个原生 macOS 机场订阅健康检查工具：测速、延迟、丢包、出口 IP、GPT / Gemini / Claude / Netflix 解锁检测。`

## Suggested Topics

GitHub topics 推荐加这些：

- `macos`
- `swift`
- `swiftui`
- `proxy`
- `subscription`
- `trojan`
- `vmess`
- `sing-box`
- `speedtest`
- `latency`
- `packet-loss`
- `network-monitoring`
- `netflix`
- `openai`
- `gemini`
- `claude`

## Social Preview / Screenshot

建议优先使用这张应用截图：

- [submax-screenshot.png](images/submax-screenshot.png)

如果以后要做 GitHub 社交预览图，建议单独做一张横向图，内容包括：

- 产品名 `SubMax`
- 一句副标题
- 一张主界面截图
- 三个关键词：`Latency` / `Bandwidth` / `Unlock Checks`

## First Release Title

推荐首个 release 标题：

`SubMax v0.1.0 - First Public Preview`

## First Release Body

可以直接复制下面这段作为首个 GitHub Release 文案：

```md
## SubMax v0.1.0

First public preview of SubMax.

SubMax is a native macOS app for checking subscription node health locally:

- import a subscription URL
- parse `trojan://` and `vmess://` nodes
- test latency, bandwidth, and packet loss
- inspect exit IP and geo info
- check reachability for Netflix / GPT / Gemini / Claude
- track history and trends
- run manual and scheduled checks

### Good fit for

- users who want to test proxy subscriptions on macOS
- users who want to know which nodes are slow, unstable, or unavailable
- users who want a local tool instead of deploying a server-side panel

### Notes

- current protocols: `trojan`, `vmess`
- runtime powered by bundled `sing-box`
- data stored locally in SQLite
- unlock checks are lightweight HTTP reachability checks, not full authenticated service validation
```

## Suggested Repo Intro

如果你要发一条 GitHub 仓库介绍帖、朋友圈或者 X / Twitter 文案，可以用这版：

```text
做了一个自己先用的原生 macOS 工具：SubMax。

它主要解决机场订阅里“哪些节点今天突然挂了、哪些节点很慢、能不能访问 GPT / Gemini / Claude / Netflix”这些问题。

支持订阅导入、节点测速、延迟/丢包/出口 IP 记录、历史趋势和本地巡检。
```

## Publish Checklist

- 仓库主页 README 已包含截图和痛点说明
- LICENSE 已补齐
- `dist/`、`.build/`、SQLite 数据已忽略
- App 图标已经替换成当前版本
- 首个 release 文案已准备
- 后续可以再补：
  - 英文 README
  - GitHub Releases 附件
