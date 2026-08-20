# WidgetKit 组件

组件是可选增强，不是默认构建的一部分。普通 App 仍可用 ad-hoc 签名本地运行；WidgetKit 需要完整 Xcode 和同一 Apple Development Team 下的 App Group。

## 准备源码

先让用户提供三个值：不存在的输出目录、App Bundle ID、App Group。不要替用户猜开发者标识。确认后运行：

```bash
python3 "$SKILL_DIR/scripts/prepare_widget_sources.py" \
  --output "/absolute/widget-project-sources" \
  --bundle-id "io.example.saved-to-action" \
  --app-group "group.io.example.saved-to-action"
```

脚本拒绝覆盖已有目录，生成 App 源码、Widget Extension 源码、两个 entitlements、Info.plist、项目设置和 `SETUP.md`。它不生成或保存证书、Team ID、Provisioning Profile。

## Xcode 边界

1. 用户在 Xcode 创建 macOS App 与 Widget Extension 两个 target。
2. 按生成目录的 `SETUP.md` 引入源码并设置 Bundle ID。
3. 两个 target 启用完全相同的 App Group；主 App Info.plist 的 `SavedToActionAppGroup` 也必须一致。
4. 主 App 首次运行后才添加组件；组件只读取 App 写入 App Group 的快照。
5. 组件中的“换一张”和“完成”更新共享本地状态；它不读取 Markdown、不修改行动 JSON。
6. 未成功签名、构建和实机验证前，不报告组件已安装。

不要提交 Xcode 用户状态、签名资料、工作区配置或任何生成后的本机绝对路径。
