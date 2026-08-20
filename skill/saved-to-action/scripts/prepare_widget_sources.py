#!/usr/bin/env python3
"""Prepare a private, signing-ready WidgetKit source package without creating credentials."""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import shutil
from pathlib import Path


def valid_identifier(value: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", value))


def main() -> int:
    parser = argparse.ArgumentParser(description="准备 Saved to Action WidgetKit 源码")
    parser.add_argument("--output", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--app-group", required=True)
    args = parser.parse_args()

    if not valid_identifier(args.bundle_id):
        parser.error("--bundle-id 必须是反向域名格式")
    if not args.app_group.startswith("group.") or not valid_identifier(args.app_group):
        parser.error("--app-group 必须是 group. 开头的反向域名")

    script_dir = Path(__file__).resolve().parent
    skill_dir = script_dir.parent
    app_source = skill_dir / "assets" / "macos-app"
    widget_source = skill_dir / "assets" / "macos-widget"
    output = Path(args.output).expanduser().resolve()
    if output.exists():
        parser.error(f"输出目录已存在，为避免覆盖已停止：{output}")

    app_target = output / "SavedToActionApp"
    widget_target = output / "SavedToActionWidgetExtension"
    shutil.copytree(app_source, app_target)
    widget_target.mkdir(parents=True)
    for name in ("WidgetStore.swift", "ActionIntents.swift", "SavedToActionWidget.swift"):
        shutil.copy2(widget_source / name, widget_target / name)

    app_info_path = app_target / "Info.plist"
    with app_info_path.open("rb") as handle:
        app_info = plistlib.load(handle)
    app_info["SavedToActionAppGroup"] = args.app_group
    with app_info_path.open("wb") as handle:
        plistlib.dump(app_info, handle, sort_keys=False)

    for template_name, target in (
        ("App.entitlements.template", app_target / "SavedToActionApp.entitlements"),
        ("Widget.entitlements.template", widget_target / "SavedToActionWidget.entitlements"),
        ("Widget-Info.plist", widget_target / "Info.plist"),
    ):
        text = (widget_source / template_name).read_text(encoding="utf-8")
        target.write_text(text.replace("__APP_GROUP__", args.app_group), encoding="utf-8")

    settings = {
        "appBundleIdentifier": args.bundle_id,
        "widgetBundleIdentifier": f"{args.bundle_id}.widget",
        "appGroup": args.app_group,
    }
    (output / "project-settings.json").write_text(
        json.dumps(settings, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    setup = f"""# Xcode 设置\n\n此目录只包含经过配置的源码，不包含证书或个人数据。\n\n1. 在 Xcode 新建 macOS App，Bundle ID 使用 `{args.bundle_id}`。\n2. 添加 macOS Widget Extension，Bundle ID 使用 `{args.bundle_id}.widget`。\n3. App target 引入 `SavedToActionApp/Sources` 与 `Resources/Board.html`。\n4. Widget target 引入 `SavedToActionWidgetExtension` 下三个 Swift 文件。\n5. 两个 target 都启用 App Groups，并选择 `{args.app_group}`。\n6. 分别使用对应目录内的 Info.plist 和 entitlements。\n7. 选择同一个 Apple Development Team 后构建；不要提交本机工作区配置或签名资料。\n\n首次运行主 App 后再添加桌面组件；组件只读取 App 写入 App Group 的本机快照。\n"""
    (output / "SETUP.md").write_text(setup, encoding="utf-8")
    print(json.dumps({"output": str(output), **settings}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
