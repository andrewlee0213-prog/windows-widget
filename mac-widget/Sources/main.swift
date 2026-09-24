// GLM Widget for macOS —— 移植自 andrewlee0213-prog/windows-widget
// 纯 AppKit 原生实现, 零第三方依赖 (Command Line Tools 的 swiftc 直接编译, 不需要 Xcode 工程)
// 数据源: open.bigmodel.cn 配额接口 / 金投网油价 / B站 wbi API / anthropic.com/research
// 构建: ./build.sh   安装: ./install.sh   配置: ~/Library/Application Support/GLMWidget/config.json

import AppKit
import CryptoKit
import Darwin

// MARK: - 基础工具

func C(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let fmtHM = DateFormatter.make("HH:mm")
let fmtMDHM = DateFormatter.make("MM-dd HH:mm")
let fmtYMD = DateFormatter.make("yyyy-MM-dd")

extension DateFormatter {
    static func make(_ f: String) -> DateFormatter {
        let d = DateFormatter()
        d.dateFormat = f
        return d
    }
}

enum Support {
    static let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GLMWidget", isDirectory: true)
    static var config: URL { root.appendingPathComponent("config.json") }
    static var posFile: URL { root.appendingPathComponent("position.json") }
    static var biliFile: URL { root.appendingPathComponent("bili-data.json") }
    static var anthFile: URL { root.appendingPathComponent("anthropic-cache.json") }
    static var logFile: URL { root.appendingPathComponent("widget.log") }
    static var lockFile: URL { root.appendingPathComponent("widget.lock") }
    static func ensure() { try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
}

func logLine(_ s: String) {
    let line = fmtMDHM.string(from: Date()) + " " + s + "\n"
    guard let d = line.data(using: .utf8) else { return }
    if let fh = FileHandle(forWritingAtPath: Support.logFile.path) {
        fh.seekToEndOfFile(); fh.write(d); try? fh.close()
    } else { try? d.write(to: Support.logFile) }
}

// 单实例: flock 锁文件, 拿不到锁说明已有实例在跑
enum SingleInstance {
    static func acquire() -> Bool {
        let fd = open(Support.lockFile.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return true }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 { close(fd); return false }
        return true
    }
}

// MARK: - HTTP / 正则 / 编码工具

func httpGet(_ url: URL, headers: [String: String] = [:], timeout: TimeInterval = 15,
             _ done: @escaping (Data?, Error?) -> Void) {
    var r = URLRequest(url: url)
    r.timeoutInterval = timeout
    for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
    URLSession.shared.dataTask(with: r) { d, _, e in done(d, e) }.resume()
}

func httpPostJSON(_ url: URL, body: [String: Any], headers: [String: String], timeout: TimeInterval = 60,
                  _ done: @escaping (Data?, Error?) -> Void) {
    var r = URLRequest(url: url)
    r.timeoutInterval = timeout
    r.httpMethod = "POST"
    r.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
    r.httpBody = try? JSONSerialization.data(withJSONObject: body)
    URLSession.shared.dataTask(with: r) { d, _, e in done(d, e) }.resume()
}

let chromeUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

// 返回捕获组数组 (g[0] = 第1组), 无匹配返回 nil
func firstMatch(_ text: String, _ pattern: String) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = text as NSString
    guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return (1..<m.numberOfRanges).map { i in
        m.range(at: i).location != NSNotFound ? ns.substring(with: m.range(at: i)) : ""
    }
}

func allMatches(_ text: String, _ pattern: String) -> [[String]] {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = text as NSString
    return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
        (1..<m.numberOfRanges).map { i in
            m.range(at: i).location != NSNotFound ? ns.substring(with: m.range(at: i)) : ""
        }
    }
}

func md5Hex(_ s: String) -> String {
    Insecure.MD5.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
}

func htmlDecode(_ s: String) -> String {
    var r = s
    let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
               "&#x27;": "'", "&#39;": "'", "&apos;": "'", "&nbsp;": " "]
    for (k, v) in map { r = r.replacingOccurrences(of: k, with: v) }
    let ns = NSMutableString(string: r)
    if let re = try? NSRegularExpression(pattern: "&#(\\d+);") {
        let ms = re.matches(in: r, range: NSRange(location: 0, length: ns.length)).reversed()
        for m in ms {
            if let v = Int((r as NSString).substring(with: m.range(at: 1))), let u = Unicode.Scalar(v) {
                ns.replaceCharacters(in: m.range, with: String(Character(u)))
            }
        }
    }
    return ns as String
}

// MARK: - 配置

final class Config {
    var key = ""
    var url = "https://open.bigmodel.cn/api/monitor/usage/quota/limit"
    var minutes: Double = 1
    var trackW: Double = 340
    var biliCookie = ""
    var biliTickMin: Double = 144
    var anthMin: Double = 1440
    var ups: [(uid: String, name: String)] = []

    static func load() -> Config {
        let c = Config()
        guard let d = try? Data(contentsOf: Support.config),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return c }
        if let v = o["Key"] as? String { c.key = v }
        if let v = o["Url"] as? String, !v.isEmpty { c.url = v }
        if let v = o["Minutes"] as? Double { c.minutes = v }
        if let v = o["Minutes"] as? Int { c.minutes = Double(v) }
        if let v = o["TrackW"] as? Double { c.trackW = v }
        if let v = o["TrackW"] as? Int { c.trackW = Double(v) }
        if let v = o["BiliCookie"] as? String { c.biliCookie = v }
        if let v = o["BiliTickMin"] as? Double { c.biliTickMin = v }
        if let v = o["BiliTickMin"] as? Int { c.biliTickMin = Double(v) }
        if let v = o["AnthMin"] as? Double { c.anthMin = v }
        if let v = o["AnthMin"] as? Int { c.anthMin = Double(v) }
        if let arr = o["BiliUps"] as? [[String: Any]] {
            c.ups = arr.compactMap { e in
                guard let uid = e["uid"] as? String else { return nil }
                return (uid, (e["name"] as? String) ?? uid)
            }
        }
        return c
    }
}

// MARK: - 数据模型

struct GLMLimit {
    var unit = 0
    var pct: Double?
    var usage: Double?
    var remaining: Double?
    var reset: Double?   // ms epoch
}

struct OilInfo {
    var price = ""
    var note = ""
    var next = ""
}

struct BiliItem: Codable {
    var uid: String
    var name: String
    var bv: String
    var title: String
    var created: Double
    var checked: String
}

struct AnthItem: Codable {
    var url: String
    var zh: String
    var pub: String   // yyyy-MM-dd
    var cat: String
}

struct PosState: Codable {
    var x: Double = 0
    var y: Double = 0
    var side: String?
    var hidden: Bool = false
}

// MARK: - UI 组件

func L(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular, _ color: NSColor) -> NSTextField {
    let l = NSTextField(labelWithString: s)
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    l.lineBreakMode = .byTruncatingTail
    l.cell?.truncatesLastVisibleLine = true
    l.translatesAutoresizingMaskIntoConstraints = false
    return l
}

func spacer(_ horizontal: Bool = true) -> NSView {
    let v = NSView()
    v.setContentHuggingPriority(.init(1), for: horizontal ? .horizontal : .vertical)
    v.setContentCompressionResistancePriority(.init(1), for: horizontal ? .horizontal : .vertical)
    return v
}

func hRow(_ spacing: CGFloat = 12) -> NSStackView {
    let r = NSStackView()
    r.orientation = .horizontal
    r.alignment = .centerY
    r.distribution = .fill
    r.spacing = spacing
    r.translatesAutoresizingMaskIntoConstraints = false
    return r
}

// 可点击的文本行 (B站/Anthropic 条目, 打开链接)
final class LinkLabel: NSTextField {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

// 进度条 (圆角轨道 + 按比例填充)
final class BarTrack: NSView {
    private let fill = NSView()
    private var fillW: NSLayoutConstraint?
    private let barH: CGFloat
    private let barR: CGFloat

    init(width: CGFloat, height: CGFloat = 14) {
        barH = height
        barR = height / 2
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        layer?.cornerRadius = barR
        fill.wantsLayer = true
        fill.layer?.cornerRadius = barR
        fill.layer?.backgroundColor = C(0x3FB950).cgColor
        addSubview(fill)
        fill.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            fill.leadingAnchor.constraint(equalTo: leadingAnchor),
            fill.centerYAnchor.constraint(equalTo: centerYAnchor),
            fill.heightAnchor.constraint(equalToConstant: barH),
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: barH),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(frac: Double, color: NSColor) {
        fillW?.isActive = false
        let f = max(0.0001, min(1, frac))
        let w = fill.widthAnchor.constraint(equalTo: widthAnchor, multiplier: f)
        w.isActive = true
        fillW = w
        fill.layer?.backgroundColor = color.cgColor
    }
}

// 玻璃拟态小卡
final class Card: NSView {
    let v: NSStackView

    init() {
        v = NSStackView()
        v.orientation = .vertical
        v.alignment = .leading
        v.distribution = .fill
        v.spacing = 8
        v.translatesAutoresizingMaskIntoConstraints = false
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            v.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            v.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            v.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    // 加入一行并拉伸到卡片全宽
    func add(_ row: NSView, stretch: Bool = true) {
        v.addArrangedSubview(row)
        if stretch {
            row.widthAnchor.constraint(equalTo: v.widthAnchor).isActive = true
        }
    }

    // 卡片头: 色条 + 标题 (+右侧状态)
    func header(_ title: String, accent: NSColor, size: CGFloat = 12) -> (NSStackView, NSTextField) {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.wantsLayer = true
        bar.layer?.backgroundColor = accent.cgColor
        bar.layer?.cornerRadius = 2
        bar.widthAnchor.constraint(equalToConstant: 8).isActive = true
        bar.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let t = L(title, size, .semibold, C(0xEAF2FB))
        let upd = L("", 10, .regular, C(0xFFFFFF, 0.80))
        let r = hRow(14)
        r.addArrangedSubview(bar)
        r.addArrangedSubview(t)
        r.addArrangedSubview(spacer())
        r.addArrangedSubview(upd)
        return (r, upd)
    }
}

// 根视图: 系统玻璃底 + 拖动 + 右键菜单 + 悬停跟踪
final class RootView: NSView {
    let effect = NSVisualEffectView()   // macOS 26 以下回退用
    let overlay = NSView()              // 描边/高光层 (回退模式下再叠午夜蓝渐变)
    let outer = NSStackView()
    private var usesLiquidGlass = false
    weak var controller: WidgetController?
    private var trackArea: NSTrackingArea?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 650, height: 300))
        wantsLayer = true

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        overlay.wantsLayer = true
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.layer?.cornerRadius = 20
        overlay.layer?.masksToBounds = true
        container.addSubview(overlay)

        outer.orientation = .vertical
        outer.alignment = .leading
        outer.distribution = .fill
        outer.spacing = 10
        outer.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 12, right: 14)
        outer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(outer)

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: container.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            outer.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            outer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            outer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
        ])

        if #available(macOS 26.0, *) {
            // 系统原生 Liquid Glass: 透明度由系统动态处理, 只叠加少量午夜蓝 tint 保持原版观感
            usesLiquidGlass = true
            let glass = NSGlassEffectView()
            glass.cornerRadius = 20
            glass.tintColor = C(0x161E3A, 0.42)
            glass.style = .regular
            if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
            glass.translatesAutoresizingMaskIntoConstraints = false
            addSubview(glass)
            glass.contentView = container
            NSLayoutConstraint.activate([
                glass.topAnchor.constraint(equalTo: topAnchor),
                glass.bottomAnchor.constraint(equalTo: bottomAnchor),
                glass.leadingAnchor.constraint(equalTo: leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: trailingAnchor),
                container.topAnchor.constraint(equalTo: glass.topAnchor),
                container.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
                container.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
                container.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            ])
        } else {
            effect.blendingMode = .behindWindow
            effect.material = .hudWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 20
            effect.layer?.masksToBounds = true
            effect.translatesAutoresizingMaskIntoConstraints = false
            addSubview(effect)
            addSubview(container)
            NSLayoutConstraint.activate([
                effect.topAnchor.constraint(equalTo: topAnchor),
                effect.bottomAnchor.constraint(equalTo: bottomAnchor),
                effect.leadingAnchor.constraint(equalTo: leadingAnchor),
                effect.trailingAnchor.constraint(equalTo: trailingAnchor),
                container.topAnchor.constraint(equalTo: topAnchor),
                container.bottomAnchor.constraint(equalTo: bottomAnchor),
                container.leadingAnchor.constraint(equalTo: leadingAnchor),
                container.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        drawGlass()
    }

    // 窗口高度变化时 setFrame 不会自动触发重排, 必须手动标记, 否则描边/高光层停留在旧位置
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    // Liquid Glass 模式只画描边+顶部高光; 回退模式再叠午夜蓝渐变模拟玻璃
    private func drawGlass() {
        guard let ol = overlay.layer else { return }
        ol.sublayers?.forEach { $0.removeFromSuperlayer() }
        if !usesLiquidGlass {
            let g = CAGradientLayer()
            g.frame = overlay.bounds
            g.colors = [C(0x161E3A, 0.78).cgColor, C(0x0D1322, 0.70).cgColor]
            g.startPoint = CGPoint(x: 0.15, y: 1)
            g.endPoint = CGPoint(x: 0.45, y: 0)
            ol.addSublayer(g)
        }

        let border = CALayer()
        border.name = "glass-border"
        border.frame = overlay.bounds
        border.cornerRadius = 20
        border.borderWidth = 1
        border.borderColor = NSColor.white.withAlphaComponent(usesLiquidGlass ? 0.28 : 0.20).cgColor
        ol.addSublayer(border)

        let hl = CAGradientLayer()
        hl.name = "glass-highlight"
        hl.frame = NSRect(x: 14, y: overlay.bounds.height - 3, width: overlay.bounds.width - 28, height: 2)
        hl.cornerRadius = 1
        hl.colors = [NSColor.white.withAlphaComponent(0.33).cgColor, NSColor.white.withAlphaComponent(0.0).cgColor]
        hl.startPoint = CGPoint(x: 0, y: 0.5)
        hl.endPoint = CGPoint(x: 1, y: 0.5)
        ol.addSublayer(hl)
    }

    // 命中测试: 除可点击行外全部归到根视图 → 整卡可拖动/可右键
    override func hitTest(_ p: NSPoint) -> NSView? {
        guard let v = super.hitTest(p) else { return nil }
        if v is LinkLabel { return v }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        controller?.beginDrag(event)
    }

    override func mouseEntered(with event: NSEvent) { controller?.mouseEnteredCard() }
    override func mouseExited(with event: NSEvent) { controller?.mouseExitedCard() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackArea = t
    }
}

// MARK: - 主控制器

final class WidgetController: NSObject {
    static let shared = WidgetController()

    var cfg = Config.load()
    var panel: NSPanel!
    var root: RootView!

    // GLM
    var cardGLM: Card!
    var levelPill: NSTextField!
    var updGLM: NSTextField!
    var bar5: BarTrack!
    var p5: NSTextField!
    var r5: NSTextField!
    var barW: BarTrack!
    var pW: NSTextField!
    var rW: NSTextField!
    var creditsL: NSTextField!
    var glmLimits: [GLMLimit]?
    var glmLevel = "Pro"
    var glmError = false
    var glmBusy = false

    // 油价
    var cardOil: Card!
    var updOil: NSTextField!
    var oilPrice: NSTextField!
    var oilNote: NSTextField!
    var oilNext: NSTextField!
    var oilInfo: OilInfo?
    var oilBusy = false

    // B站
    var cardBili: Card!
    var updBili: NSTextField!
    var biliList: NSStackView!
    var biliData: [String: BiliItem] = [:]
    var biliBusy = false
    var biliRoundTimer: Timer?

    // Anthropic
    var cardAnth: Card!
    var updAnth: NSTextField!
    var anthList: NSStackView!
    var anthZh: [String: String] = [:]
    var anthItems: [AnthItem] = []
    var anthBusy = false

    // 刷新进度面板
    var cardRP: Card!
    var rpCount: NSTextField!
    var rpBar: BarTrack!
    var rpLines: [NSTextField] = []
    var rpDone = 0
    var rpBusy = false
    var rpHideTimer: Timer?

    // 窗口/贴边
    var topmost = true
    var dockEnabled = false
    var dockSide = ""      // "" | "L" | "R" | "T"
    var dockHidden = false
    var hideTimer: Timer?
    var menuTop: NSMenuItem!
    var menuDock: NSMenuItem!
    var pullTab: NSView!

    let weekChars = Array("日一二三四五六")

    // ---- 启动 ----

    func start() {
        Support.ensure()
        root = RootView()
        root.controller = self
        buildCards()

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 650, height: 300),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = root
        buildMenu()

        restoreOrPlace()
        panel.orderFrontRegardless()
        DispatchQueue.main.async { self.refreshHeight() }

        // GLM: 立即取数 + 定时
        if cfg.key.isEmpty {
            updGLM.stringValue = "未配置 API Key"
        } else {
            fetchGLM { _ in }
            Timer.scheduledTimer(withTimeInterval: cfg.minutes * 60, repeats: true) { [weak self] _ in
                self?.fetchGLM { _ in }
            }
        }

        // 油价: 立即 + 24h (失败30分钟后重试)
        fetchOil { ok in self.applyOilResult(ok) }

        // B站: 回放缓存 → 20秒后首轮
        loadBiliCache()
        renderBili()
        scheduleBiliRound(after: 20)

        // Anthropic: 回放缓存 → 60秒后首抓
        loadAnthCache()
        renderAnthropic()
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.fetchAnthropic { ok in self?.applyAnthResult(ok) }
        }

        // 调试: --snapshot 离屏渲染窗口内容到 /tmp/widget-snap.png 后退出 (无需屏幕录制权限)
        if CommandLine.arguments.contains("--snapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self, let root = self.root else { exit(1) }
                root.layoutSubtreeIfNeeded()
                let b = root.bounds
                let scale: CGFloat = 2
                guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(b.width * scale),
                                                 pixelsHigh: Int(b.height * scale), bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0),
                      let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
                rep.size = b.size
                ctx.cgContext.translateBy(x: 0, y: CGFloat(rep.pixelsHigh))
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                root.layer?.render(in: ctx.cgContext)
                try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/widget-snap.png"))
                print("root bounds=\(root.bounds)")
                print("overlay frame=\(root.overlay.frame) bounds=\(root.overlay.bounds)")
                for sub in root.overlay.layer?.sublayers ?? [] {
                    print("layer [\(sub.name ?? "?")] frame=\(sub.frame)")
                }
                exit(0)
            }
        }
    }

    func shutdown() { savePos() }

    // ---- UI 构建 ----

    private func buildCards() {
        // GLM 卡
        cardGLM = Card()
        let (h1, u1) = cardGLM.header("GLM Coding Plan", accent: C(0x5B9DFF), size: 13)
        updGLM = u1
        let pillWrap = NSView()
        pillWrap.translatesAutoresizingMaskIntoConstraints = false
        pillWrap.wantsLayer = true
        pillWrap.layer?.backgroundColor = C(0x5B9DFF, 0.15).cgColor
        pillWrap.layer?.cornerRadius = 8
        levelPill = L("Pro", 10, .regular, C(0x8FC2FF))
        pillWrap.addSubview(levelPill)
        NSLayoutConstraint.activate([
            levelPill.topAnchor.constraint(equalTo: pillWrap.topAnchor, constant: 2),
            levelPill.bottomAnchor.constraint(equalTo: pillWrap.bottomAnchor, constant: -2),
            levelPill.leadingAnchor.constraint(equalTo: pillWrap.leadingAnchor, constant: 12),
            levelPill.trailingAnchor.constraint(equalTo: pillWrap.trailingAnchor, constant: -12),
        ])
        h1.insertArrangedSubview(pillWrap, at: 2)
        cardGLM.add(h1)

        func quotaRow(_ label: String) -> (BarTrack, NSTextField, NSTextField) {
            let lab = L(label, 11, .regular, C(0xFFFFFF, 0.92))
            // 标签固定列宽: "5小时"/"本周"字数不同, 不固定则两行进度条起点错开
            lab.widthAnchor.constraint(equalToConstant: 40).isActive = true
            let bar = BarTrack(width: cfg.trackW)
            let pct = L("--", 12, .semibold, C(0xEAF2FB))
            pct.alignment = .right
            pct.widthAnchor.constraint(equalToConstant: 48).isActive = true
            let rst = L("", 10, .regular, C(0xFFFFFF, 0.85))
            rst.setContentCompressionResistancePriority(.required, for: .horizontal)
            let r = hRow(12)
            r.addArrangedSubview(lab)
            r.addArrangedSubview(bar)
            r.addArrangedSubview(pct)
            r.addArrangedSubview(spacer())
            r.addArrangedSubview(rst)   // 重置时间贴行尾, 对齐 Windows 版
            cardGLM.add(r)
            return (bar, pct, rst)
        }
        (bar5, p5, r5) = quotaRow("5小时")
        (barW, pW, rW) = quotaRow("本周")
        creditsL = L("", 10, .regular, C(0xFFFFFF, 0.85))
        cardGLM.add(creditsL, stretch: false)
        root.outer.addArrangedSubview(cardGLM)
        cardGLM.widthAnchor.constraint(equalTo: root.outer.widthAnchor).isActive = true

        // 油价卡
        cardOil = Card()
        let (h2, u2) = cardOil.header("上海油价", accent: C(0xF0A830))
        updOil = u2
        cardOil.add(h2)
        let oilRow = hRow(8)
        let oilLab = L("95汽油", 11, .regular, C(0xFFFFFF, 0.92))
        oilPrice = L("--", 13, .semibold, C(0xEAF2FB))
        let oilUnit = L("元/升", 10, .regular, C(0xFFFFFF, 0.85))
        oilRow.addArrangedSubview(oilLab)
        oilRow.addArrangedSubview(spacer())
        oilRow.addArrangedSubview(oilPrice)
        oilRow.addArrangedSubview(oilUnit)
        cardOil.add(oilRow)
        oilNote = L("", 10, .regular, C(0xFFFFFF, 0.85))
        oilNext = L("", 10, .regular, C(0xFFFFFF, 0.85))
        cardOil.add(oilNote, stretch: false)
        cardOil.add(oilNext, stretch: false)
        root.outer.addArrangedSubview(cardOil)
        cardOil.widthAnchor.constraint(equalTo: root.outer.widthAnchor).isActive = true

        // B站卡
        cardBili = Card()
        let (h3, u3) = cardBili.header("B站 · 关注更新", accent: C(0xFB7299))
        updBili = u3
        cardBili.add(h3)
        biliList = NSStackView()
        biliList.orientation = .vertical
        biliList.alignment = .leading
        biliList.spacing = 6
        biliList.translatesAutoresizingMaskIntoConstraints = false
        cardBili.add(biliList)
        root.outer.addArrangedSubview(cardBili)
        cardBili.widthAnchor.constraint(equalTo: root.outer.widthAnchor).isActive = true

        // Anthropic 卡
        cardAnth = Card()
        let (h4, u4) = cardAnth.header("Anthropic 研究", accent: C(0xD97757))
        updAnth = u4
        cardAnth.add(h4)
        anthList = NSStackView()
        anthList.orientation = .vertical
        anthList.alignment = .leading
        anthList.spacing = 6
        anthList.translatesAutoresizingMaskIntoConstraints = false
        cardAnth.add(anthList)
        root.outer.addArrangedSubview(cardAnth)
        cardAnth.widthAnchor.constraint(equalTo: root.outer.widthAnchor).isActive = true

        // 刷新进度卡 (默认隐藏)
        cardRP = Card()
        let (h5, u5) = cardRP.header("刷新进度", accent: C(0x5B9DFF))
        rpCount = u5
        rpCount.stringValue = "0/4"
        cardRP.add(h5)
        rpBar = BarTrack(width: cfg.trackW, height: 6)
        cardRP.add(rpBar, stretch: false)
        for i in 0..<4 {
            let line = L("", 10, .regular, C(0xFFFFFF, 0.92))
            rpLines.append(line)
            cardRP.add(line, stretch: false)
        }
        cardRP.isHidden = true
        root.outer.addArrangedSubview(cardRP)
        cardRP.widthAnchor.constraint(equalTo: root.outer.widthAnchor).isActive = true

        // 角标 + 页脚
        pullTab = NSView()
        pullTab.translatesAutoresizingMaskIntoConstraints = false
        pullTab.wantsLayer = true
        pullTab.layer?.backgroundColor = C(0x5B9DFF).cgColor
        pullTab.layer?.cornerRadius = 3
        pullTab.isHidden = true
        root.addSubview(pullTab)
        NSLayoutConstraint.activate([
            pullTab.widthAnchor.constraint(equalToConstant: 6),
            pullTab.heightAnchor.constraint(equalToConstant: 64),
        ])

        let footer = L("拖动移动 · 右键菜单", 10, .regular, C(0xFFFFFF, 0.85))
        let fr = hRow(0)
        fr.addArrangedSubview(spacer())
        fr.addArrangedSubview(footer)
        fr.addArrangedSubview(spacer())
        root.outer.addArrangedSubview(fr)
    }

    private func buildMenu() {
        let menu = NSMenu()
        let mRefresh = NSMenuItem(title: "立即刷新", action: #selector(menuRefresh), keyEquivalent: "")
        mRefresh.target = self
        menu.addItem(mRefresh)
        menuTop = NSMenuItem(title: "窗口置顶", action: #selector(menuTopmost), keyEquivalent: "")
        menuTop.target = self
        menuTop.state = .on
        menu.addItem(menuTop)
        menuDock = NSMenuItem(title: "贴边隐藏", action: #selector(menuDockToggle), keyEquivalent: "")
        menuDock.target = self
        menu.addItem(menuDock)
        let mExit = NSMenuItem(title: "退出", action: #selector(menuExit), keyEquivalent: "")
        mExit.target = self
        menu.addItem(mExit)
        root.menu = menu
    }

    @objc func menuRefresh() { refreshAll() }

    @objc func menuTopmost() {
        topmost.toggle()
        menuTop.state = topmost ? .on : .off
        panel.level = topmost ? .floating : .normal
    }

    @objc func menuDockToggle() {
        if dockEnabled {
            undock()
        } else {
            dockEnabled = true
            menuDock.state = .on
            dock(nearestSide(), hide: true)
        }
    }

    @objc func menuExit() {
        savePos()
        NSApp.terminate(nil)
    }

    // ---- 窗口定位 / 高度 ----

    private func restoreOrPlace() {
        var placed = false
        if let d = try? Data(contentsOf: Support.posFile),
           let p = try? JSONDecoder().decode(PosState.self, from: d) {
            panel.setFrameOrigin(NSPoint(x: p.x, y: p.y))
            if NSScreen.screens.contains(where: { $0.frame.intersects(panel.frame) }) {
                placed = true
                if let s = p.side {
                    dockEnabled = true
                    menuDock.state = .on
                    dock(s, hide: p.hidden)
                }
            }
        }
        if !placed {
            if let vf = NSScreen.main?.visibleFrame {
                let w = panel.frame.width
                panel.setFrameOrigin(NSPoint(x: vf.maxX - w - 20, y: vf.minY + 20))
            }
        }
    }

    private func savePos() {
        var p = PosState()
        let f = panel?.frame ?? .zero
        p.x = Double(f.minX)
        p.y = Double(f.minY)
        p.side = dockSide.isEmpty ? nil : dockSide
        p.hidden = dockHidden
        if let d = try? JSONEncoder().encode(p) { try? d.write(to: Support.posFile) }
    }

    // 内容高度变化后重设窗口 (顶边固定)
    func refreshHeight() {
        guard let p = panel else { return }
        root.layoutSubtreeIfNeeded()
        var h = root.outer.fittingSize.height
        if h < 100 { h = 100 }
        var f = p.frame
        if abs(f.height - h) > 0.5 {
            f.origin.y += f.height - h
            f.size.height = h
            p.setFrame(f, display: true)
        }
        if !dockSide.isEmpty {
            dock(dockSide, hide: dockHidden)
        }
    }

    // ---- 拖动 / 贴边隐藏 ----

    func beginDrag(_ event: NSEvent) {
        cancelHideTimer()
        // 隐藏状态先瞬间复位到贴边显示位, 再进入拖动
        if dockHidden { showDock(animated: false) }
        panel.performDrag(with: event)
        dragEnded()
    }

    private func dragEnded() {
        savePos()
        if dockEnabled {
            let s = nearestSide()
            if let gap = edgeGap(of: s), gap <= 40 {
                dock(s, hide: true)
            } else {
                undock()   // 拖离边缘自动解除贴边
            }
        }
        refreshHeight()
    }

    private func edgeGap(of s: String) -> CGFloat? {
        guard let b = screenOf() else { return nil }
        let f = panel.frame
        switch s {
        case "L": return f.minX - b.frame.minX
        case "R": return b.frame.maxX - f.maxX
        case "T": return b.frame.maxY - f.maxY
        default: return nil
        }
    }

    private func nearestSide() -> String {
        let cands: [(String, CGFloat)] = [
            ("L", edgeGap(of: "L") ?? .greatestFiniteMagnitude),
            ("R", edgeGap(of: "R") ?? .greatestFiniteMagnitude),
            ("T", edgeGap(of: "T") ?? .greatestFiniteMagnitude),
        ]
        return cands.min { $0.1 < $1.1 }?.0 ?? "R"
    }

    private func screenOf() -> NSScreen? {
        let f = panel.frame
        let c = NSPoint(x: f.midX, y: f.midY)
        return NSScreen.screens.first { $0.frame.contains(c) } ?? NSScreen.main
    }

    func dock(_ s: String, hide: Bool) {
        dockSide = s
        dockHidden = false
        guard let scr = screenOf() else { return }
        var f = panel.frame
        switch s {
        case "L": f.origin.x = scr.frame.minX
        case "R": f.origin.x = scr.frame.maxX - f.width
        case "T": f.origin.y = scr.frame.maxY - f.height
        default: break
        }
        f.origin.y = min(max(f.origin.y, scr.frame.minY), scr.frame.maxY - f.height)
        f.origin.x = min(max(f.origin.x, scr.frame.minX), scr.frame.maxX - f.width)
        panel.setFrame(f, display: true)
        updateTab()
        if hide { hideDock() }
        savePos()
    }

    private func hiddenFrame(for s: String, screen scr: NSScreen) -> NSRect {
        var f = panel.frame
        switch s {
        case "L": f.origin.x = scr.frame.minX - f.width + 22
        case "R": f.origin.x = scr.frame.maxX - 22
        case "T": f.origin.y = scr.frame.maxY - 22
        default: break
        }
        return f
    }

    private func visibleDockFrame(for s: String, screen scr: NSScreen) -> NSRect {
        var f = panel.frame
        switch s {
        case "L": f.origin.x = scr.frame.minX
        case "R": f.origin.x = scr.frame.maxX - f.width
        case "T": f.origin.y = scr.frame.maxY - f.height
        default: break
        }
        return f
    }

    func hideDock() {
        guard !dockSide.isEmpty, let scr = screenOf() else { return }
        dockHidden = true
        updateTab()
        animateTo(hiddenFrame(for: dockSide, screen: scr))
    }

    func showDock(animated: Bool = true) {
        guard !dockSide.isEmpty, let scr = screenOf() else { return }
        dockHidden = false
        updateTab()
        let target = visibleDockFrame(for: dockSide, screen: scr)
        if animated { animateTo(target) } else { panel.setFrame(target, display: true) }
    }

    private func animateTo(_ f: NSRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(f, display: true)
        }
    }

    func undock() {
        dockSide = ""
        dockHidden = false
        dockEnabled = false
        menuDock.state = .off
        pullTab.isHidden = true
        if let scr = screenOf() {
            var f = panel.frame
            f.origin.x = min(max(f.origin.x, scr.frame.minX), scr.frame.maxX - f.width)
            f.origin.y = min(max(f.origin.y, scr.frame.minY), scr.frame.maxY - f.height)
            panel.setFrame(f, display: true)
        }
        savePos()
    }

    private func updateTab() {
        pullTab.isHidden = !(dockEnabled && dockHidden)
        guard !pullTab.isHidden else { return }
        let bb = root.bounds
        switch dockSide {
        case "L":
            pullTab.frame.origin = NSPoint(x: bb.width - 14 - 6, y: bb.height / 2 - 32)
        case "R":
            pullTab.frame.origin = NSPoint(x: 14, y: bb.height / 2 - 32)
        case "T":
            pullTab.frame.origin = NSPoint(x: bb.width / 2 - 3, y: 12)
        default: break
        }
    }

    func mouseEnteredCard() {
        cancelHideTimer()
        if dockEnabled && dockHidden { showDock() }
    }

    func mouseExitedCard() {
        guard dockEnabled else { return }
        cancelHideTimer()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
            guard let self, self.dockEnabled else { return }
            // 收起前确认鼠标真的不在挂件上 (防边缘1px进出抖动)
            if self.panel.frame.contains(NSEvent.mouseLocation) { return }
            self.hideDock()
        }
    }

    private func cancelHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    // ---- GLM ----

    func fetchGLM(_ done: @escaping (Bool) -> Void) {
        guard !glmBusy else { done(false); return }
        glmBusy = true
        var req = URLRequest(url: URL(string: cfg.url)!)
        req.timeoutInterval = 15
        req.setValue(cfg.key, forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { [weak self] d, _, e in
            DispatchQueue.main.async {
                guard let self else { return }
                self.glmBusy = false
                if e != nil || d == nil {
                    self.glmError = true
                    self.applyGLM()
                    logLine("GLM fetch error: \(e?.localizedDescription ?? "nil")")
                    done(false)
                    return
                }
                if let o = (try? JSONSerialization.jsonObject(with: d!)) as? [String: Any],
                   let data = o["data"] as? [String: Any],
                   let limits = data["limits"] as? [[String: Any]], !limits.isEmpty {
                    self.glmLimits = limits.map { l in
                        var g = GLMLimit()
                        g.unit = (l["unit"] as? Int) ?? Int((l["unit"] as? Double) ?? 0)
                        g.pct = l["percentage"] as? Double
                        g.usage = l["usage"] as? Double
                        g.remaining = l["remaining"] as? Double
                        g.reset = l["nextResetTime"] as? Double
                        return g
                    }
                    if let lv = data["level"] as? String, !lv.isEmpty { self.glmLevel = lv }
                    self.glmError = false
                    self.applyGLM()
                    done(true)
                } else {
                    self.glmError = true
                    self.applyGLM()
                    done(false)
                }
            }
        }.resume()
    }

    private func setQuotaRow(_ bar: BarTrack, _ pct: NSTextField, _ rst: NSTextField, _ item: GLMLimit?, weekly: Bool) {
        guard let item else {
            bar.set(frac: 0, color: C(0x3FB950))
            pct.stringValue = "--"
            rst.stringValue = ""
            return
        }
        var rem: Double = 100
        if let u = item.usage, let r = item.remaining, u > 0 {
            rem = (r / u * 100).rounded()
        } else if let p = item.pct {
            rem = 100 - p
        }
        rem = min(100, max(0, rem))
        let color = rem <= 20 ? C(0xF85149) : (rem <= 50 ? C(0xD29922) : C(0x3FB950))
        bar.set(frac: rem / 100, color: color)
        pct.stringValue = "\(Int(rem))%"
        if let ms = item.reset {
            let d = Date(timeIntervalSince1970: ms / 1000)
            if weekly {
                let wd = weekChars[Calendar.current.component(.weekday, from: d) - 1]
                rst.stringValue = "周\(wd) \(fmtHM.string(from: d))"
            } else {
                rst.stringValue = fmtHM.string(from: d) + " 重置"
            }
        } else {
            rst.stringValue = ""
        }
    }

    private func applyGLM() {
        guard let limits = glmLimits else { return }
        let five = limits.first { $0.unit == 3 } ?? limits.first
        let week = limits.first { $0.unit == 6 } ?? limits.dropFirst().first
        setQuotaRow(bar5, p5, r5, five, weekly: false)
        setQuotaRow(barW, pW, rW, week, weekly: true)
        let lv = glmLevel
        levelPill.stringValue = lv.isEmpty ? "Pro" : lv.prefix(1).uppercased() + lv.dropFirst()
        if glmError {
            updGLM.stringValue = fmtHM.string(from: Date()) + " · 接口错误(保留旧值)"
            creditsL.stringValue = creditsL.stringValue   // 保留
        } else {
            updGLM.stringValue = fmtHM.string(from: Date()) + " 更新"
            var credits = ""
            if let f = five, let w = week, let fu = f.usage, let fr = f.remaining, let wu = w.usage, let wr = w.remaining {
                credits = "5h剩\(Int(fr))/\(Int(fu)) · 本周剩\(Int(wr))/\(Int(wu))"
            }
            creditsL.stringValue = credits
        }
    }

    // ---- 油价 ----

    private func fetchOil(_ done: @escaping (OilInfo?) -> Void) {
        guard !oilBusy else { done(nil); return }
        oilBusy = true
        guard let u1 = URL(string: "https://www.cngold.org/crude/shanghai.html") else { oilBusy = false; done(nil); return }
        httpGet(u1, headers: ["User-Agent": chromeUA], timeout: 12) { d, e in
            guard let d, let html = String(data: d, encoding: .utf8),
                  let ri = html.range(of: "hq_table1") else {
                DispatchQueue.main.async { self.oilBusy = false; done(nil) }
                return
            }
            let seg = String(html[ri.upperBound...].prefix(1000))
            guard let m = firstMatch(seg, "<td>([\\d.]+)</td>\\s*<td>([\\d.]+)</td>\\s*<td>([\\d.]+)</td>\\s*<td>([\\d.]+)</td>") else {
                DispatchQueue.main.async { self.oilBusy = false; done(nil) }
                return
            }
            var info = OilInfo()
            info.price = m[2]   // 列序固定: 89#/92#/95#/0#柴油 → 第3列
            var note = ""
            if let dd = firstMatch(html, "class=.data.>\\s*(\\d{4}-\\d{2}-\\d{2})") {
                note += String(dd[0].suffix(5)) + "起"
            }
            let rows = allMatches(html, "<td class=.data.>\\s*\\d{4}-\\d{2}-\\d{2}\\s*</td>([\\s\\S]*?)</tr>")
            if rows.count >= 2 {
                let nums = allMatches(rows[1][0], "class=.nums.>\\s*([\\d.]+)")
                if nums.count >= 3, let prev = Double(nums[2][0]), let cur = Double(info.price) {
                    let diff = (cur * 100).rounded() / 100 - prev
                    let sign = diff >= 0 ? "+" : ""
                    note += " · 上期\(nums[2][0])(\(sign)\(String(format: "%.2f", diff)))"
                }
            }
            info.note = note
            // 下次调价窗口 + 预估 (独立降级, 失败保留上次内容)
            guard let u2 = URL(string: "https://energy.cngold.org/") else {
                DispatchQueue.main.async { self.oilBusy = false; done(info) }
                return
            }
            httpGet(u2, headers: ["User-Agent": chromeUA], timeout: 12) { d2, _ in
                let finishInfo = { (next: String) in
                    DispatchQueue.main.async {
                        self.oilBusy = false
                        info.next = next
                        done(info)
                    }
                }
                guard let d2, let h2 = String(data: d2, encoding: .utf8) else { finishInfo(""); return }
                // 首页预测标题: 今日(9月24日)油价预计上调450元/吨 —— 标题里的日期就是下次调价窗口日
                var forecastDate = ""
                var dirn = ""
                var amt = ""
                if let mm = firstMatch(h2, "今日\\((\\d{1,2}月\\d{1,2}日)\\)油价预计(上调|下调|搁浅)(\\d+)?元/吨") {
                    forecastDate = mm[0]; dirn = mm[1]; amt = mm[2]
                }
                var win2 = forecastDate.isEmpty ? "" : forecastDate + "24时"
                var range: (String, String, String)?
                guard let ma = firstMatch(h2, "<a href=\"([^\"]+)\"[^>]*title=\"油价调整最新消息"),
                      let artURL = URL(string: ma[0]) else {
                    finishInfo(self.forecastText(dirn, amt, range)); return
                }
                httpGet(artURL, headers: ["User-Agent": chromeUA], timeout: 12) { d3, _ in
                    if let d3, let art = String(data: d3, encoding: .utf8) {
                        if win2.isEmpty {
                            // 文章兜底: 正文开头常是上一期已过窗口, 取第一个"今天及以后"的日期
                            for w in allMatches(art, "(\\d{1,2})月(\\d{1,2})日24时") {
                                if let m = Int(w[0]), let dd = Int(w[1]), self.isUpcoming(month: m, day: dd) {
                                    win2 = "\(m)月\(dd)日24时"
                                    break
                                }
                            }
                        }
                        if let md = firstMatch(art, "<meta name=\"description\" content=\"([^\"]+)\""),
                           let rg = firstMatch(md[0], "(上涨|下跌)([\\d.]+)元(?:/升)?-([\\d.]+)元/升") {
                            range = (rg[0], rg[1], rg[2])
                        }
                    }
                    var line = ""
                    if !win2.isEmpty { line = "下次调价 " + win2 }
                    let ftxt = self.forecastText(dirn, amt, range)
                    if !ftxt.isEmpty { line += (line.isEmpty ? "" : " · ") + ftxt }
                    finishInfo(line)
                }
            }
        }
    }

    // 预估文案: 预计涨/跌/搁浅 + 折合升价区间(文章description) 或 元/吨÷1350 兜底
    private func forecastText(_ dirn: String, _ amt: String, _ range: (String, String, String)?) -> String {
        guard !dirn.isEmpty else { return "" }
        var ftxt = "预计" + (dirn == "上调" ? "涨" : (dirn == "下调" ? "跌" : "搁浅"))
        if let rg = range, ((dirn == "上调" && rg.0 == "上涨") || (dirn == "下调" && rg.0 == "下跌")) {
            ftxt += "\(rg.1)~\(rg.2)"
        } else if let a = Double(amt), a > 0 {
            ftxt += String((a / 1350 * 100).rounded() / 100)
        }
        return ftxt
    }

    // "M月D日"是否在今天及以后 (跨年周期按来年算)
    private func isUpcoming(month: Int, day: Int) -> Bool {
        let cal = Calendar.current
        var c = cal.dateComponents([.year], from: Date())
        c.month = month
        c.day = day
        guard var d = cal.date(from: c) else { return false }
        if d >= cal.startOfDay(for: Date()) { return true }
        d = cal.date(byAdding: .year, value: 1, to: d) ?? d
        return d >= cal.startOfDay(for: Date())
    }

    private func applyOilResult(_ info: OilInfo?) {
        if let info {
            oilInfo = info
            oilPrice.stringValue = info.price
            oilNote.stringValue = info.note
            oilNext.stringValue = info.next
            updOil.stringValue = fmtHM.string(from: Date()) + " 更新"
            updOil.textColor = C(0xFFFFFF, 0.80)
            oilTimer24h()
        } else {
            oilNote.stringValue = "取价失败"
            oilNote.textColor = C(0xF85149)
            updOil.stringValue = fmtHM.string(from: Date()) + " 失败"
            oilTimer30m()
        }
    }

    private func oilTimer24h() {
        Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: false) { [weak self] _ in
            self?.fetchOil { ok in self?.applyOilResult(ok) }
        }
    }

    private func oilTimer30m() {
        Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: false) { [weak self] _ in
            self?.fetchOil { ok in self?.applyOilResult(ok) }
        }
    }

    // ---- B站 (wbi 签名 API + Cookie) ----

    private let wbiTab: [Int] = [46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
                                 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40, 61,
                                 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36,
                                 20, 34, 44, 52]
    private var wbiCache: (key: String, exp: Date)?

    private func biliHeaders() -> [String: String] {
        var h = ["User-Agent": chromeUA,
                 "Referer": "https://space.bilibili.com/",
                 "Origin": "https://www.bilibili.com"]
        if !cfg.biliCookie.isEmpty { h["Cookie"] = cfg.biliCookie }
        return h
    }

    private func getWbiKey(_ done: @escaping (String?) -> Void) {
        if let c = wbiCache, c.exp > Date() { done(c.key); return }
        guard let u = URL(string: "https://api.bilibili.com/x/web-interface/nav") else { done(nil); return }
        httpGet(u, headers: biliHeaders(), timeout: 12) { d, _ in
            guard let d,
                  let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let data = o["data"] as? [String: Any],
                  let wbi = data["wbi_img"] as? [String: Any],
                  let img = wbi["img_url"] as? String,
                  let sub = wbi["sub_url"] as? String else {
                DispatchQueue.main.async { done(nil) }
                return
            }
            let imgKey = img.split(separator: "/").last.map { $0.split(separator: ".").first.map(String.init) ?? "" } ?? ""
            let subKey = sub.split(separator: "/").last.map { $0.split(separator: ".").first.map(String.init) ?? "" } ?? ""
            let raw = Array(imgKey + subKey)
            let tab = self.wbiTab
            let key = String(tab.prefix(32).compactMap { i in i < raw.count ? raw[i] : nil })
            DispatchQueue.main.async {
                self.wbiCache = (key, Date().addingTimeInterval(24 * 3600))
                done(key)
            }
        }
    }

    private func wbiSign(_ params: [String: String], key: String) -> [String: String] {
        var p = params
        p["wts"] = String(Int(Date().timeIntervalSince1970))
        var cleaned: [String: String] = [:]
        for (k, v) in p { cleaned[k] = String(v.filter { !"'()*".contains($0) }) }
        let allow = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        let q = cleaned.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allow) ?? $0.value)" }
            .joined(separator: "&")
        cleaned["w_rid"] = md5Hex(q + key)
        return cleaned
    }

    enum BiliErr: Error { case risk, nologin, empty, network
        var msg: String {
            switch self {
            case .risk: return "风控拦截·需有效Cookie"
            case .nologin: return "登录失效·请更新Cookie"
            case .empty: return "拉取为空"
            case .network: return "网络超时"
            }
        }
    }

    private func fetchBili(_ up: (uid: String, name: String), _ done: @escaping (Result<BiliItem, BiliErr>) -> Void) {
        getWbiKey { [weak self] key in
            guard let self, let key else {
                DispatchQueue.main.async { done(.failure(.risk)) }
                return
            }
            let params = self.wbiSign([
                "mid": up.uid, "ps": "1", "tid": "0", "pn": "1", "keyword": "",
                "order": "pubdate", "platform": "web", "web_location": "1551101", "order_avoided": "true",
            ], key: key)
            var comps = URLComponents(string: "https://api.bilibili.com/x/space/wbi/arc/search")!
            comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
            httpGet(comps.url!, headers: self.biliHeaders(), timeout: 15) { d, e in
                DispatchQueue.main.async {
                    if e != nil || d == nil { done(.failure(.network)); return }
                    guard let o = (try? JSONSerialization.jsonObject(with: d!)) as? [String: Any],
                          let code = o["code"] as? Int else { done(.failure(.empty)); return }
                    if code == -352 || code == -412 { done(.failure(.risk)); return }
                    if code == -101 { done(.failure(.nologin)); return }
                    guard code == 0,
                          let data = o["data"] as? [String: Any],
                          let list = data["list"] as? [String: Any],
                          let vlist = list["vlist"] as? [[String: Any]],
                          let v = vlist.first,
                          let bv = v["bvid"] as? String else { done(.failure(.empty)); return }
                    let item = BiliItem(uid: up.uid, name: up.name, bv: bv,
                                        title: (v["title"] as? String) ?? "（无标题）",
                                        created: (v["created"] as? Double) ?? ((v["created"] as? Int).map(Double.init) ?? 0),
                                        checked: fmtMDHM.string(from: Date()))
                    done(.success(item))
                }
            }
        }
    }

    private func loadBiliCache() {
        guard let d = try? Data(contentsOf: Support.biliFile),
              let arr = try? JSONDecoder().decode([BiliItem].self, from: d) else { return }
        for it in arr { biliData[it.uid] = it }
    }

    private func saveBili() {
        let arr = cfg.ups.compactMap { biliData[$0.uid] }
        if let d = try? JSONEncoder().encode(arr) { try? d.write(to: Support.biliFile) }
    }

    private func renderBili() {
        biliList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var ready = 0
        for up in cfg.ups {
            let row = LinkLabel(labelWithString: "")
            row.font = .systemFont(ofSize: 11)
            row.lineBreakMode = .byTruncatingTail
            row.cell?.truncatesLastVisibleLine = true
            row.translatesAutoresizingMaskIntoConstraints = false
            if let d = biliData[up.uid] {
                ready += 1
                var title = d.title
                if title.hasPrefix("【\(up.name)】") { title = String(title.dropFirst(up.name.count + 2)) }
                let attr = NSMutableAttributedString(string: "· \(up.name) | \(title)", attributes: [
                    .font: NSFont.systemFont(ofSize: 11), .foregroundColor: C(0xC9D6E2),
                ])
                if Calendar.current.isDateInToday(Date(timeIntervalSince1970: d.created)) {
                    attr.append(NSAttributedString(string: " New", attributes: [
                        .font: NSFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: C(0xFB7299),
                    ]))
                }
                row.attributedStringValue = attr
                row.toolTip = "\(up.name)：\(d.title)  (点击打开视频)"
                row.onClick = { NSWorkspace.shared.open(URL(string: "https://www.bilibili.com/video/\(d.bv)")!) }
            } else {
                // 还没核对到: 占位行, 不让卡片看起来是空的
                row.attributedStringValue = NSAttributedString(string: "· \(up.name) | 等待核对…", attributes: [
                    .font: NSFont.systemFont(ofSize: 11), .foregroundColor: C(0xFFFFFF, 0.85),
                ])
            }
            biliList.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: biliList.widthAnchor).isActive = true
        }
        if ready > 0 {
            updBili.stringValue = "\(fmtHM.string(from: Date())) 更新(\(ready)/\(cfg.ups.count))"
        } else if cfg.ups.isEmpty {
            updBili.stringValue = "未配置 UP, 见 config.json"
        } else if updBili.stringValue.isEmpty {
            updBili.stringValue = "首次核对中…"
        }
        refreshHeight()
    }

    private func scheduleBiliRound(after seconds: TimeInterval) {
        biliRoundTimer?.invalidate()
        biliRoundTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.biliRound(manual: false, perUp: nil) { _ in }
        }
    }

    /// 一轮全量核对; manual 时逐 UP 上报进度
    func biliRound(manual: Bool, perUp: ((Int, Int, String, Bool, String) -> Void)?, _ done: @escaping (Bool) -> Void) {
        guard !biliBusy else { done(false); return }
        guard !cfg.ups.isEmpty else {
            updBili.stringValue = "未配置 UP, 见 config.json"
            done(true)
            return
        }
        biliBusy = true
        var idx = 0
        var fails: [(String, String)] = []
        var okc = 0

        func next() {
            if idx >= cfg.ups.count { finish(); return }
            let up = cfg.ups[idx]
            if manual { perUp?(idx + 1, cfg.ups.count, up.name, false, "核对中…") }
            fetchBili(up) { res in
                switch res {
                case .success(let item):
                    self.biliData[up.uid] = item
                    okc += 1
                    self.saveBili()
                    self.renderBili()
                    if manual { perUp?(idx + 1, self.cfg.ups.count, up.name, true, "✓") }
                case .failure(let e):
                    fails.append((up.name, e.msg))
                    if manual { perUp?(idx + 1, self.cfg.ups.count, up.name, false, "✗ " + e.msg) }
                }
                idx += 1
                next()
            }
        }

        func finish() {
            biliBusy = false
            if okc > 0 {
                updBili.stringValue = "\(fmtHM.string(from: Date())) 更新(\(okc)/\(cfg.ups.count))"
                updBili.textColor = C(0xFFFFFF, 0.80)
            }
            if fails.isEmpty {
                scheduleBiliRound(after: cfg.biliTickMin * 60)
            } else {
                let msg = fails.map { "\($0.0):\($0.1)" }.joined(separator: " ")
                updBili.stringValue = msg
                updBili.textColor = fails.contains { $0.1.contains("登录") || $0.1.contains("Cookie") } ? C(0xF0A830) : C(0xF85149)
                // 失败补试: 风控/登录类等60分钟, 其他3分钟
                let risky = fails.contains { $0.1.contains("Cookie") || $0.1.contains("风控") }
                scheduleBiliRound(after: risky ? 60 * 60 : 3 * 60)
            }
            done(fails.isEmpty)
        }

        next()
    }

    // ---- Anthropic 研究 ----

    private func loadAnthCache() {
        guard let d = try? Data(contentsOf: Support.anthFile),
              let arr = try? JSONDecoder().decode([AnthItem].self, from: d) else { return }
        for it in arr {
            anthZh[it.url] = it.zh
            anthItems.append(it)
        }
    }

    private func saveAnth() {
        if let d = try? JSONEncoder().encode(anthItems) { try? d.write(to: Support.anthFile) }
    }

    private func translateLines(_ lines: [String], _ done: @escaping ([String]) -> Void) {
        guard !cfg.key.isEmpty, !lines.isEmpty else { done([]); return }
        let joined = lines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let prompt = "Translate these research article titles from English to Chinese. Output only the translations, one per line, keeping the same numbering."
        let body: [String: Any] = [
            "model": "glm-4-flash",
            "messages": [["role": "user", "content": prompt + "\n" + joined]],
        ]
        httpPostJSON(URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!, body: body,
                     headers: ["Authorization": "Bearer " + cfg.key]) { d, _ in
            DispatchQueue.main.async {
                guard let d,
                      let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                      let choices = o["choices"] as? [[String: Any]],
                      let msg = choices.first?["message"] as? [String: Any],
                      let content = msg["content"] as? String else { done([]); return }
                var out = [String](repeating: "", count: lines.count)
                for line in content.components(separatedBy: "\n") {
                    if let m = firstMatch(line, "^\\s*(\\d+)[\\.、]\\s*(.+)$"),
                       let i = Int(m[0]), i >= 1, i <= lines.count {
                        out[i - 1] = m[1].trimmingCharacters(in: .whitespaces)
                    }
                }
                done(out)
            }
        }
    }

    private func fetchAnthropic(_ done: @escaping (Bool) -> Void) {
        guard !anthBusy else { done(false); return }
        anthBusy = true
        guard let u = URL(string: "https://www.anthropic.com/research") else { anthBusy = false; done(false); return }
        httpGet(u, headers: ["User-Agent": chromeUA], timeout: 20) { d, e in
            guard let d, let html = String(data: d, encoding: .utf8) else {
                logLine("anth fetch error: \(e?.localizedDescription ?? "nil")")
                DispatchQueue.main.async { self.anthBusy = false; done(false) }
                return
            }
            // Publications 表: 链接 / 日期 / 分类 / 标题
            var arts: [(href: String, ts: Double, title: String, cat: String)] = []
            var seen: Set<String> = []
            let df = DateFormatter.make("MMM d, yyyy")
            df.locale = Locale(identifier: "en_US_POSIX")
            for m in allMatches(html, "<li><a href=\"(/research/[^\"]+)\"[^>]*>\\s*<div[^>]*>\\s*<time[^>]*>([^<]+)</time>\\s*<span[^>]*>([^<]*)</span>\\s*</div>\\s*<span[^>]*>([^<]+)</span>") {
                let href = "https://www.anthropic.com" + m[0]
                guard !seen.contains(href), let dt = df.date(from: m[1].trimmingCharacters(in: .whitespaces)) else { continue }
                seen.insert(href)
                let cleanTitle = htmlDecode(m[3].replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression, range: nil)).trimmingCharacters(in: .whitespaces)
                arts.append((href, dt.timeIntervalSince1970, cleanTitle, m[2]))
            }
            guard !arts.isEmpty else {
                DispatchQueue.main.async { self.anthBusy = false; done(false) }
                return
            }
            let latest = arts.sorted { $0.ts > $1.ts }.prefix(3)
            let need = latest.filter { self.anthZh[$0.href] == nil }
            self.translateLines(need.map { $0.title }) { zhs in
                for (i, z) in zhs.enumerated() where !z.isEmpty {
                    self.anthZh[need[i].href] = z
                }
                self.anthItems = latest.map { a in
                    AnthItem(url: a.href, zh: self.anthZh[a.href] ?? a.title,
                             pub: fmtYMD.string(from: Date(timeIntervalSince1970: a.ts)), cat: a.cat)
                }
                self.saveAnth()
                DispatchQueue.main.async {
                    self.anthBusy = false
                    self.renderAnthropic()
                    done(true)
                }
            }
        }
    }

    private func applyAnthResult(_ ok: Bool) {
        if ok {
            updAnth.stringValue = "\(fmtHM.string(from: Date())) 更新(\(anthItems.count))"
            updAnth.textColor = C(0xFFFFFF, 0.80)
            // 24h 后再刷
            Timer.scheduledTimer(withTimeInterval: cfg.anthMin * 60, repeats: false) { [weak self] _ in
                self?.fetchAnthropic { ok in self?.applyAnthResult(ok) }
            }
        } else {
            updAnth.stringValue = "\(fmtHM.string(from: Date())) 抓取失败"
            updAnth.textColor = C(0xF85149)
            Timer.scheduledTimer(withTimeInterval: 20 * 60, repeats: false) { [weak self] _ in
                self?.fetchAnthropic { ok in self?.applyAnthResult(ok) }
            }
        }
    }

    private func renderAnthropic() {
        anthList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let today = fmtYMD.string(from: Date())
        for a in anthItems.prefix(3) {
            let row = LinkLabel(labelWithString: "")
            row.lineBreakMode = .byTruncatingTail
            row.cell?.truncatesLastVisibleLine = true
            row.translatesAutoresizingMaskIntoConstraints = false
            let attr = NSMutableAttributedString(string: "· \(a.zh)", attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: C(0xC9D6E2),
            ])
            if !a.cat.isEmpty {
                attr.append(NSAttributedString(string: "  \(a.cat)", attributes: [
                    .font: NSFont.systemFont(ofSize: 9), .foregroundColor: C(0xFFFFFF, 0.85),
                ]))
            }
            if a.pub == today {
                attr.append(NSAttributedString(string: " New", attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: C(0xFB7299),
                ]))
            }
            row.attributedStringValue = attr
            row.toolTip = "点击打开原文"
            row.onClick = { NSWorkspace.shared.open(URL(string: a.url)!) }
            anthList.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: anthList.widthAnchor).isActive = true
        }
        if anthItems.isEmpty {
            updAnth.stringValue = "加载中…"
        }
        refreshHeight()
    }

    // ---- 手动全量刷新 (底部进度面板, 逐板块一行一步) ----

    private func setRp(_ idx: Int, _ txt: String, _ color: NSColor) {
        rpLines[idx - 1].stringValue = txt
        rpLines[idx - 1].textColor = color
    }

    private func rpAdvance() {
        rpDone += 1
        rpCount.stringValue = "\(rpDone)/4"
        rpBar.set(frac: Double(rpDone) / 4, color: C(0x5B9DFF))
    }

    func refreshAll() {
        guard !rpBusy else { return }
        rpBusy = true
        rpHideTimer?.invalidate()
        cardRP.isHidden = false
        rpDone = 0
        rpCount.stringValue = "0/4"
        rpBar.set(frac: 0, color: C(0x5B9DFF))
        setRp(1, "GLM 额度 · 刷新中…", C(0xEAF2FB))
        setRp(2, "上海油价 · 等待", C(0xFFFFFF, 0.92))
        setRp(3, "B站关注 · 等待", C(0xFFFFFF, 0.92))
        setRp(4, "Anthropic 研究 · 等待", C(0xFFFFFF, 0.92))
        refreshHeight()

        // 第1步 GLM
        if cfg.key.isEmpty {
            setRp(1, "GLM 额度 · 未配置 API Key", C(0xF0A830))
            rpAdvance()
            rpStepOil()
        } else {
            fetchGLM { ok in
                if ok {
                    self.setRp(1, "GLM 额度 ✓ \(fmtHM.string(from: Date())):\(self.secondStr())", C(0x3FB950))
                } else {
                    self.setRp(1, "GLM 额度 · 接口错误,已保留旧值", C(0xF0A830))
                }
                self.rpAdvance()
                self.rpStepOil()
            }
        }
    }

    private func secondStr() -> String {
        let f = DateFormatter.make("ss")
        return f.string(from: Date())
    }

    private func rpStepOil() {
        setRp(2, "上海油价 · 刷新中…", C(0xEAF2FB))
        fetchOil { info in
            if let info {
                self.oilInfo = info
                self.oilPrice.stringValue = info.price
                self.oilNote.stringValue = info.note
                self.oilNote.textColor = C(0xFFFFFF, 0.85)
                self.oilNext.stringValue = info.next
                self.updOil.stringValue = "\(fmtHM.string(from: Date())) 更新"
                self.updOil.textColor = C(0xFFFFFF, 0.80)
                self.setRp(2, "上海油价 ✓ \(info.price)元/升", C(0x3FB950))
            } else {
                self.setRp(2, "上海油价 ✗ 失败,保留旧值", C(0xF85149))
            }
            self.rpAdvance()
            self.rpStepBili()
        }
    }

    private func rpStepBili() {
        setRp(3, "B站关注 · 全量核对 \(cfg.ups.count) 个UP…", C(0xEAF2FB))
        biliRound(manual: true, perUp: { i, n, name, okFlag, msg in
            let col: NSColor = okFlag ? C(0x3FB950) : (msg.contains("✗") ? C(0xF85149) : C(0xEAF2FB))
            self.setRp(3, "B站 · \(i)/\(n) \(name) \(msg)", col)
        }) { ok in
            self.rpAdvance()
            self.rpStepAnth()
        }
    }

    private func rpStepAnth() {
        setRp(4, "Anthropic 研究 · 刷新中…", C(0xEAF2FB))
        fetchAnthropic { ok in
            if ok {
                self.setRp(4, "Anthropic 研究 ✓", C(0x3FB950))
            } else {
                self.setRp(4, "Anthropic 研究 ✗ 抓取失败", C(0xF85149))
            }
            self.rpAdvance()
            self.rpBusy = false
            self.rpHideTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.cardRP.isHidden = true
                self.refreshHeight()
            }
        }
    }
}

// MARK: - 入口

final class AppDelegate: NSObject, NSApplicationDelegate {
    let ctl = WidgetController.shared
    func applicationDidFinishLaunching(_ notification: Notification) { ctl.start() }
    func applicationWillTerminate(_ notification: Notification) { ctl.shutdown() }
}

Support.ensure()
guard SingleInstance.acquire() else { exit(0) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.appearance = NSAppearance(named: .darkAqua)
let del = AppDelegate()
app.delegate = del
app.run()
