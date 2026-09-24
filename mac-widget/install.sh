#!/bin/bash
# 一次性安装: 编译 → 装到 ~/Applications → 生成配置 → 注册 LaunchAgent(开机自启 + 看门狗)
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

DEST="$HOME/Applications"
mkdir -p "$DEST"
rm -rf "$DEST/GLM Widget.app"
cp -R "build/GLM Widget.app" "$DEST/"

# 配置文件 (已存在则不动)
CONF_DIR="$HOME/Library/Application Support/GLMWidget"
mkdir -p "$CONF_DIR"
if [ ! -f "$CONF_DIR/config.json" ]; then
    cp config.example.json "$CONF_DIR/config.json"
    echo "已生成配置: $CONF_DIR/config.json  (请编辑填入 GLM API Key)"
fi

# LaunchAgent: RunAtLoad 开机自启, KeepAlive 崩溃自动拉起 (等价 Windows 版看门狗)
PLIST="$HOME/Library/LaunchAgents/cn.andrewlee0213.glm-widget.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>cn.andrewlee0213.glm-widget</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DEST/GLM Widget.app/Contents/MacOS/GLM Widget</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key><false/>
    </dict>
</dict>
</plist>
XML
launchctl bootout "gui/$(id -u)/cn.andrewlee0213.glm-widget" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "安装完成, 正在启动…"
echo "  应用位置: $DEST/GLM Widget.app"
echo "  配置文件: $CONF_DIR/config.json"
echo "  日志文件: $CONF_DIR/widget.log"
echo "  卸载: launchctl bootout gui/\$(id -u)/cn.andrewlee0213.glm-widget && rm -f '$PLIST'"
open "$DEST/GLM Widget.app"
