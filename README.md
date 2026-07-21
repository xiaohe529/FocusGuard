# FocusGuard — macOS 专注力守护工具

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-orange)]()

FocusGuard 是一个 macOS 桌面应用，帮助你在需要专注时屏蔽网站、App 和网络，减少干扰。

> 适合：考研党、远程工作者、需要写代码/写论文但总想刷 B 站微博的人。

## 功能

| 模块 | 说明 |
|------|------|
| **网站屏蔽** | 通过 `/etc/hosts` 将网站域名指向 127.0.0.1，支持自定义规则 |
| **App 屏蔽** | 定时扫描运行中的应用，强制关闭被屏蔽的 App |
| **网络拦截** | 修改系统 DNS 为无效地址，全局断网（不影响局域网） |
| **专注计时** | 设置倒计时，计时结束前无法取消屏蔽（需密码） |
| **延时屏蔽** | 先开始干活，N 分钟后自动开启屏蔽 |
| **定时提醒** | 未屏蔽时每隔 N 分钟弹窗提醒"该开启了" |
| **密码保护** | 停止屏蔽需输入密码，增加操作摩擦防止一时冲动 |

## 安装

1. 从 [GitHub](https://github.com/xiaohe529/FocusGuard/releases) 或 [Gitee](https://gitee.com/xiaohe529/focus-guard/releases) 下载 `FocusGuard-v*.zip`
2. 双击解压，把 `FocusGuard.app` **拖入「应用程序」文件夹**
3. **首次打开**：右键点 App → 按住 Option → 选「打开」（这是 macOS 对未签名 App 的安全拦截，一次性的）

> 首次运行会请求管理员权限安装后台助手，安装后屏蔽操作静默执行。

### 如果提示「已损坏，无法打开」

这是 macOS Gatekeeper 拦截未签名 App，不是真的损坏。终端运行：

```bash
xattr -cr /Applications/FocusGuard.app
```

然后重新打开即可。

### 从源码构建

```bash
git clone https://github.com/xiaohe529/FocusGuard.git
# 或国内镜像
git clone https://gitee.com/xiaohe529/focus-guard.git
cd FocusGuard
./build-app.sh          # Debug 版
# 或
./build-app.sh release  # Release 版
open .build/FocusGuard.app
```

要求：Xcode 16+ / Command Line Tools，macOS 14+

## 架构

```
FocusGuard.app
├── FocusGuard          # 主应用（用户界面 + 业务逻辑）
├── FocusGuardHelper    # 后台助手（以 root 运行，仅做 /etc/hosts 写入和 DNS 设置）
│                       #   LaunchDaemon 安装到 /Library/LaunchDaemons/
├── FocusGuardHelperShared  # XPC 协议定义（app ↔ helper 通信接口）
```

安全要点：
- App 与 helper 通过 **NSXPCConnection** 通信，helper 以 root 权限运行
- 通信需验证共享 token（仅 root 可读，权限 600），**恒定时间比较**防止时序攻击
- Helper 端**命令白名单**，只允许写入预定义路径的 hosts 文件和 networksetup DNS
- App 内密码存储于 **Keychain**，验证使用恒定时间比较

## 屏蔽原理

- **网站屏蔽**：在 `/etc/hosts` 中插入 `127.0.0.1 <域名>`，使浏览器无法解析目标网站
- **App 屏蔽**：每 5 秒轮询 `NSWorkspace.runningApplications`，对匹配到的 App 先 `terminate()`，2 秒后若仍运行则 `kill(SIGKILL)`
- **网络拦截**：`networksetup -setdnsservers Wi-Fi 127.0.0.1`，DNS 指向本机无效端口，阻止所有域名解析

> 网络拦截依赖系统 DNS 设置。若使用公司 Wi-Fi 的 DHCP 自动下发 DNS，路由器 DNS 可能覆盖系统设置导致拦截无效。建议在「系统设置 → 网络 → Wi-Fi → DNS」中手动指定 DNS。

## 项目结构

```
FocusGuard/
├── Sources/
│   ├── FocusGuard/          # 主应用
│   │   ├── Models/          # BlockRule, FocusTimerState
│   │   ├── Views/           # SwiftUI 视图
│   │   ├── Services/        # 各服务（Hosts/App/WiFi Blocker, Keychain, Helper Installer 等）
│   │   ├── AppState.swift   # 全局状态管理
│   │   └── FocusGuardApp.swift
│   ├── FocusGuardHelper/    # 后台 LaunchDaemon
│   └── FocusGuardHelperShared/  # 共享协议与常量
├── BundleResources/         # Info.plist 等
├── Package.swift            # SwiftPM 配置
├── build-app.sh             # 构建 → .app bundle
├── make-release.sh          # .app → zip 发布包
└── LICENSE
```

## License

MIT © 2025 FocusGuard Contributors

---

## 致谢

如果你觉得有用，欢迎给个 ⭐ star。Bug 反馈和功能建议提 Issue 即可。
