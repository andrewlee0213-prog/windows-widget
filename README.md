# Windows 桌面信息挂件

一个纯 PowerShell + WPF 的 Windows 置顶桌面小组件，零第三方依赖（Windows PowerShell 5.1 开箱即用），聚合四路信息源：

| 板块 | 内容 | 数据源 | 节奏 |
|---|---|---|---|
| GLM 额度 | Coding Plan 5小时窗 / 本周用量双进度条 + 剩余点数 | open.bigmodel.cn 配额接口 | 1 分钟 |
| 上海油价 | 95# 现价 / 上期价对比 / 下次调价窗口与预估 | 金投网 | 24 小时 |
| B站关注 | 自选 UP 主最新投稿，当日新稿亮 New 标 | 桥接浏览器渲染空间页 | 全量一轮 144 分钟 |
| Anthropic 研究 | 官网 Publications 表最新 3 篇（glm-4-flash 翻译标题 + 分类） | anthropic.com/research | 24 小时 |

其他特性：

- **玻璃拟态分层卡片 UI**（午夜蓝渐变 + 半透明小卡 + 高光描边，纯 WPF 实现）
- **三边贴边隐藏**：勾选后拖到上/左/右边缘自动缩进，鼠标碰边缘滑出（带动画，副屏不窜屏）
- **手动刷新进度面板**：右键"立即刷新"逐板块一行一步显示执行状态（✓/✗/超时），完成 8 秒后自动收起
- **B站按需浏览器**：轮询时自动拉起桥接 Edge、拿完数据优雅关闭（Cookie 落盘不丢登录态），平时桌面无残留
- **看门狗自愈**：挂件进程意外退出 60 秒内自动拉起；单实例互斥

## 安装

要求：Windows 10/11，PowerShell 5.1（系统自带）。

```powershell
git clone https://github.com/andrewlee0213-prog/windows-widget.git
cd windows-widget
Copy-Item config.example.ps1 config.ps1
notepad config.ps1      # 填入 GLM API Key
powershell -File setup.ps1   # 修 UTF-8 BOM + 建启动快捷方式
```

启动：双击桌面 `GLM-widget.lnk`（或开始菜单启动项里的快捷方式，开机自启）。

### B站板块的额外依赖（可选）

B站对无登录 API 请求一律 `-352` 设备风控，所以该板块走**桥接浏览器**方案：

1. 安装 [OpenCLI](https://opencli.info)，其 `browser lc` 命令可驱动一个可见 Edge 实例
2. 下载 opencli 浏览器扩展，解压到本目录 `opencli-extension/`
3. 挂件会在本目录维护一个独立 profile 的 Edge（`edge-profile/`），首次在该窗口里登录B站
4. 登录态由 Cookie 维持，失效时挂件 B站板块会提示"请重新登录B站"并自动弹出登录页，扫码即恢复

不需要 B站功能的话，把 `config.ps1` 里 `BiliUps` 清空即可，其余板块不受影响。

## 目录结构

```
windows-widget/
├── glm-widget.ps1        主程序（UI + 数据轮询 + B站后台引擎，约1200行）
├── config.example.ps1    配置模板（复制为 config.ps1 使用）
├── launch.vbs            隐藏控制台启动器
├── watchdog.vbs          进程看门狗
├── setup.ps1             一次性安装（BOM 修复 + 快捷方式）
└── tools/
    ├── check-api.ps1     GLM 配额接口连通性检查
    ├── dump-widget.ps1   UIAutomation 读取挂件文本（排障用）
    └── probe-live.ps1    窗口探针 + 截图 + 重启（排障用）
```

## 架构

```
┌─ UI 线程 (WPF Dispatcher) ────────────────────────────┐
│  渲染/拖动/贴边动画/右键菜单/刷新进度面板                  │
│  GLM 渲染定时器(10s读json)  油价/Anthropic定时器          │
│  B站观察器(2s): 应用后台引擎结果→落盘渲染                  │
└──────────────┬───────────────────────────────────────┘
               │ 同步哈希表 (data/progress/status/dirty/done/kick)
┌──────────────┴───────────────────────────────────────┐
│ 后台线程                                               │
│  GLM fetch引擎: 60s取数写json(支持立即触发文件)           │
│  B站引擎: 按需拉起桥接Edge→全量核对UP→优雅关闭            │
│    └ opencli → 桥接Edge(独立profile) → B站空间页DOM      │
└──────────────────────────────────────────────────────┘
```

设计要点：

- **UI 线程零网络等待**：所有取数在后台线程，B站轮询再慢也不冻结界面
- **失败语义分级**：网络超时（3 分钟快速重试）/ 登录失效（亮登录页等人扫，60 分钟温和重试）/ 桥接僵死（连续 3 轮超时杀进程重启）
- **接口容错**：GLM 接口返回错误体时保留最后一份好数据并标注"接口错误"，不覆盖不闪空
- **数据持久化**：各板块落盘 JSON，重启即时回放

## 已知限制（都是踩过的坑）

- `.ps1` 必须 UTF-8 BOM，否则 zh-CN Windows 下中文字符串乱码（setup.ps1 自动修复）
- B站登录态寿命不定（数小时到数天），失效会提示扫码；空间设了"登录可见"的 UP 最先暴露
- 桥接 Edge 窗口不能最小化/移出屏幕（Chromium 节流），引擎每轮自动归位
- 多显示器 DPI 混缩场景的坐标换算已处理（物理像素 ÷ 缩放系数），但极端布局未验证
- WPF `AllowsTransparency` 窗口上 DWM 亚克力/ACCENT blur 会渲染成纯黑或透明幽灵，玻璃感用渐变模拟

## License

MIT
