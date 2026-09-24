# macOS 桌面信息挂件

[windows-widget](https://github.com/andrewlee0213-prog/windows-widget) 的 Mac 版移植。纯 AppKit 原生实现，零第三方依赖（只需系统自带的 Command Line Tools，`swiftc` 直接编译），聚合四路信息源：

| 板块 | 内容 | 数据源 | 节奏 |
|---|---|---|---|
| GLM 额度 | Coding Plan 5小时窗 / 本周用量双进度条 + 剩余点数 | open.bigmodel.cn 配额接口 | 1 分钟 |
| 上海油价 | 95# 现价 / 上期价对比 / 下次调价窗口与预估 | 金投网 | 24 小时（失败 30 分钟重试） |
| B站关注 | 自选 UP 主最新投稿，当日新稿亮 New 标 | B站 wbi 签名 API + 你的 Cookie | 全量一轮 144 分钟 |
| Anthropic 研究 | 官网 Publications 最新 3 篇（glm-4-flash 翻译标题 + 分类） | anthropic.com/research | 24 小时 |

与 Windows 版的差异：

- **毛玻璃是真的**：NSVisualEffectView 实时模糊壁纸，叠加午夜蓝渐变保持原版观感（Windows 版因 WPF 渲染缺陷只能用不透明渐变模拟）
- **B站走 API 而不是桥接浏览器**：实现 wbi 签名直接调空间接口，把浏览器里的 Cookie 粘进配置即可，无需 OpenCLI/Edge
- 看门狗用 LaunchAgent `KeepAlive` 实现（异常退出自动拉起），单实例用 flock 锁文件

其他保持一致的特性：拖动移动、右键菜单（立即刷新 / 窗口置顶 / 贴边隐藏 / 退出）、贴边隐藏（拖到上/左/右边缘自动缩进留 8pt 角标，鼠标碰边滑出）、手动刷新进度面板（逐板块一行一步 ✓/✗）、数据落盘重启即时回放、失败保留旧值。

## 安装

要求：macOS 12+，Xcode Command Line Tools（没有的话先 `xcode-select --install`）。

```bash
git clone https://github.com/andrewlee0213-prog/mac-widget.git   # 或直接用本目录
cd mac-widget
./install.sh
```

install.sh 会：编译 → 装到 `~/Applications/GLM Widget.app` → 生成配置 → 注册 LaunchAgent（开机自启 + 看门狗）→ 启动。

### 填配置

编辑 `~/Library/Application Support/GLMWidget/config.json`：

```json
{
  "Key": "你的GLM_API_Key",
  "Url": "https://open.bigmodel.cn/api/monitor/usage/quota/limit",
  "Minutes": 1,
  "TrackW": 340,
  "BiliCookie": "SESSDATA=xxx; buvid3=xxx",
  "BiliUps": [
    { "uid": "520155988", "name": "示例UP主一" }
  ],
  "BiliTickMin": 144,
  "AnthMin": 1440
}
```

- **Key**：https://open.bigmodel.cn 控制台获取，同一把 Key 同时用于配额查询和标题翻译
- **BiliCookie**：浏览器登录 B站 → F12 → 网络 → 任一 bilibili 请求 → 请求头 Cookie 整串复制（至少含 `SESSDATA` 和 `buvid3`）。Cookie 失效时挂件会提示"请更新Cookie"
- **BiliUps**：uid = UP主空间页地址里那串数字。不需要 B站板块就留空数组 `[]`
- 改完配置右键挂件 → 退出 → 重新打开生效

## 目录结构

```
mac-widget/
├── Sources/main.swift    主程序（UI + 四路数据 + 贴边隐藏，约1100行）
├── config.example.json   配置模板
├── build.sh              编译成 build/GLM Widget.app
└── install.sh            一次性安装（编译 + LaunchAgent）
```

## 架构

单线程事件模型：所有网络请求走 URLSession 后台回调，UI 只在主线程更新（等价 Windows 版"UI 线程零网络等待"）。各板块独立定时器 + 失败语义分级（网络超时快速重试 / Cookie 失效提示换 Cookie / 接口错误保留旧值）。数据持久化在 `~/Library/Application Support/GLMWidget/`（bili-data.json / anthropic-cache.json / position.json / widget.log）。

## 卸载

```bash
launchctl bootout gui/$(id -u)/cn.andrewlee0213.glm-widget
rm -f ~/Library/LaunchAgents/cn.andrewlee0213.glm-widget.plist
rm -rf ~/Applications/GLM\ Widget.app
```

## License

MIT
