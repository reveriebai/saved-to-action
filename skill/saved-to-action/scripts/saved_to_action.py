#!/usr/bin/env python3
"""Deterministic workspace tooling for the saved-to-action skill."""

from __future__ import annotations

import argparse
import datetime as dt
import fnmatch
import hashlib
import json
import os
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


CONFIG_NAME = "saved-to-action.json"
DEFAULT_CATEGORIES = [
    "工作与项目",
    "学习与研究",
    "创作与表达",
    "健康与生活",
    "工具与系统",
    "待分类",
]
DEFAULT_EXCLUDES = [
    ".git/**",
    ".obsidian/**",
    "**/.git/**",
    "**/.obsidian/**",
    "**/.trash/**",
]


class SavedToActionError(RuntimeError):
    pass


@dataclass(frozen=True)
class Note:
    source_id: str
    identity_kind: str
    source_name: str
    source_root: Path
    relative_path: str
    absolute_path: Path
    title: str
    saved_at: str
    modified_at: float

    def public_dict(self, include_absolute_path: bool = True) -> dict[str, Any]:
        result = {
            "sourceId": self.source_id,
            "identityKind": self.identity_kind,
            "sourceName": self.source_name,
            "relativePath": self.relative_path,
            "title": self.title,
            "savedAt": self.saved_at,
        }
        if include_absolute_path:
            result["absolutePath"] = str(self.absolute_path)
        return result


def now_iso() -> str:
    return dt.datetime.now().astimezone().replace(microsecond=0).isoformat()


def today_iso() -> str:
    return dt.date.today().isoformat()


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SavedToActionError(f"文件不存在：{path}") from exc
    except json.JSONDecodeError as exc:
        raise SavedToActionError(f"JSON 无法解析：{path}: {exc}") from exc
    if not isinstance(value, dict):
        raise SavedToActionError(f"JSON 顶层必须是对象：{path}")
    return value


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    encoded = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
        json.loads(temporary.read_text(encoding="utf-8"))
        os.replace(temporary, path)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def parse_frontmatter(text: str) -> dict[str, str]:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    values: dict[str, str] = {}
    for line in lines[1:]:
        if line.strip() == "---":
            return values
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if ":" not in line:
            return {}
        key, raw_value = line.split(":", 1)
        key = key.strip()
        if not key or key.startswith("-"):
            continue
        value = raw_value.strip().strip('"\'')
        if value:
            values[key] = value
    return {}


def parse_date(value: str | None, fallback_timestamp: float) -> str:
    if value:
        candidate = value.strip()
        if len(candidate) >= 10:
            try:
                return dt.date.fromisoformat(candidate[:10]).isoformat()
            except ValueError:
                pass
    return dt.datetime.fromtimestamp(fallback_timestamp).date().isoformat()


def matches_pattern(relative_path: str, pattern: str) -> bool:
    relative_path = relative_path.replace(os.sep, "/")
    if fnmatch.fnmatch(relative_path, pattern):
        return True
    return pattern.startswith("**/") and fnmatch.fnmatch(relative_path, pattern[3:])


def included(relative_path: str, includes: Iterable[str], excludes: Iterable[str]) -> bool:
    return any(matches_pattern(relative_path, pattern) for pattern in includes) and not any(
        matches_pattern(relative_path, pattern) for pattern in excludes
    )


def source_id_for(
    source_name: str,
    relative_path: str,
    frontmatter: dict[str, str],
    identity_keys: Iterable[str],
) -> tuple[str, str]:
    for key in identity_keys:
        value = frontmatter.get(key)
        if value:
            digest = hashlib.sha256(
                f"frontmatter\0{source_name}\0{key}\0{value}".encode("utf-8")
            ).hexdigest()
            return f"note:{digest}", f"frontmatter:{key}"
    digest = hashlib.sha256(f"path\0{source_name}\0{relative_path}".encode("utf-8")).hexdigest()
    return f"note:{digest}", "relative-path"


def parse_source_argument(value: str) -> dict[str, str]:
    if "=" not in value:
        raise SavedToActionError("来源必须使用 名称=/绝对/路径 格式")
    name, raw_path = value.split("=", 1)
    name = name.strip()
    path = Path(raw_path).expanduser()
    if not name:
        raise SavedToActionError("来源名称不能为空")
    if not path.is_absolute():
        raise SavedToActionError(f"来源路径必须是绝对路径：{path}")
    if not path.is_dir():
        raise SavedToActionError(f"来源目录不存在：{path}")
    return {"name": name, "path": str(path.resolve())}


def scan_notes(config: dict[str, Any]) -> list[Note]:
    sources = config.get("sources")
    if not isinstance(sources, list) or not sources:
        raise SavedToActionError("配置至少需要一个来源目录")
    includes = config.get("include", ["**/*.md"])
    excludes = config.get("exclude", DEFAULT_EXCLUDES)
    recursive = bool(config.get("recursive", True))
    identity_keys = config.get("identityKeys", ["uid", "id"])
    notes: list[Note] = []
    seen_ids: dict[str, str] = {}
    seen_names: set[str] = set()

    for source in sources:
        name = source.get("name")
        path_value = source.get("path")
        if not isinstance(name, str) or not name or name in seen_names:
            raise SavedToActionError(f"来源名称无效或重复：{name!r}")
        seen_names.add(name)
        if not isinstance(path_value, str):
            raise SavedToActionError(f"来源 {name} 缺少路径")
        root = Path(path_value).expanduser().resolve()
        if not root.is_dir():
            raise SavedToActionError(f"来源目录不存在：{root}")
        iterator = root.rglob("*.md") if recursive else root.glob("*.md")
        for path in iterator:
            if path.is_symlink() or not path.is_file():
                continue
            resolved = path.resolve()
            try:
                relative = resolved.relative_to(root).as_posix()
            except ValueError:
                continue
            if not included(relative, includes, excludes):
                continue
            try:
                text = resolved.read_text(encoding="utf-8")
            except UnicodeDecodeError as exc:
                raise SavedToActionError(f"Markdown 不是 UTF-8：{resolved}") from exc
            stat = resolved.stat()
            frontmatter = parse_frontmatter(text)
            source_id, identity_kind = source_id_for(name, relative, frontmatter, identity_keys)
            if source_id in seen_ids:
                raise SavedToActionError(
                    f"笔记身份重复：{seen_ids[source_id]} 与 {name}/{relative}"
                )
            seen_ids[source_id] = f"{name}/{relative}"
            timestamp = getattr(stat, "st_birthtime", stat.st_mtime)
            title = frontmatter.get("title") or resolved.stem
            saved_at = parse_date(frontmatter.get("created") or frontmatter.get("date"), timestamp)
            notes.append(
                Note(
                    source_id=source_id,
                    identity_kind=identity_kind,
                    source_name=name,
                    source_root=root,
                    relative_path=relative,
                    absolute_path=resolved,
                    title=title,
                    saved_at=saved_at,
                    modified_at=stat.st_mtime,
                )
            )
    return sorted(notes, key=lambda note: (note.saved_at, note.modified_at, note.relative_path))


def workspace_paths(workspace: Path) -> tuple[Path, Path]:
    workspace = workspace.expanduser().resolve()
    config_path = workspace / CONFIG_NAME
    return config_path, workspace / "Data" / "actions.json"


def load_workspace(workspace: Path) -> tuple[Path, dict[str, Any], Path, dict[str, Any]]:
    workspace = workspace.expanduser().resolve()
    config_path = workspace / CONFIG_NAME
    config = read_json(config_path)
    raw_data_path = config.get("dataPath", "Data/actions.json")
    if not isinstance(raw_data_path, str):
        raise SavedToActionError("dataPath 必须是字符串")
    data_path = (workspace / raw_data_path).resolve()
    try:
        data_path.relative_to(workspace)
    except ValueError as exc:
        raise SavedToActionError("dataPath 必须位于工作目录内") from exc
    data = read_json(data_path)
    return workspace, config, data_path, data


def baseline_record(note: Note) -> dict[str, Any]:
    return {
        "sourceId": note.source_id,
        "sourceName": note.source_name,
        "relativePath": note.relative_path,
        "title": note.title,
        "processedAt": today_iso(),
        "mode": "baseline",
        "actionIds": [],
    }


def initialize_workspace(
    workspace: Path,
    sources: list[dict[str, str]],
    mode: str,
    latest: int,
    categories: list[str] | None = None,
) -> dict[str, Any]:
    workspace = workspace.expanduser().resolve()
    config_path, data_path = workspace_paths(workspace)
    if config_path.exists() or data_path.exists():
        raise SavedToActionError(f"工作目录已经初始化：{workspace}")
    config = {
        "version": 1,
        "language": "zh-CN",
        "recursive": True,
        "include": ["**/*.md"],
        "exclude": DEFAULT_EXCLUDES,
        "identityKeys": ["uid", "id"],
        "categories": categories or DEFAULT_CATEGORIES,
        "sources": sources,
        "dataPath": "Data/actions.json",
    }
    notes = scan_notes(config)
    if mode == "future":
        baseline = notes
    elif mode == "latest":
        if latest < 1:
            raise SavedToActionError("latest 模式要求 --latest 大于 0")
        baseline = notes[:-latest] if latest < len(notes) else []
    elif mode == "all":
        baseline = []
    else:
        raise SavedToActionError(f"未知首次导入模式：{mode}")
    data = {
        "version": 1,
        "updatedAt": now_iso(),
        "processedNotes": [baseline_record(note) for note in baseline],
        "actions": [],
    }
    validate_data(config, data, notes)
    atomic_write_json(config_path, config)
    atomic_write_json(data_path, data)
    return {
        "workspace": str(workspace),
        "configPath": str(config_path),
        "dataPath": str(data_path),
        "notesFound": len(notes),
        "baselineCount": len(baseline),
        "pendingCount": len(notes) - len(baseline),
        "mode": mode,
    }


def safe_relative_path(value: Any) -> bool:
    if not isinstance(value, str) or not value or value.startswith("/"):
        return False
    return all(part not in {"", ".", ".."} for part in value.split("/"))


def pending_notes(notes: list[Note], data: dict[str, Any]) -> list[Note]:
    processed = {
        item.get("sourceId")
        for item in data.get("processedNotes", [])
        if isinstance(item, dict)
    }
    return [note for note in notes if note.source_id not in processed]


def validate_data(config: dict[str, Any], data: dict[str, Any], notes: list[Note] | None = None) -> None:
    if config.get("version") != 1:
        raise SavedToActionError("工作区配置 version 必须为 1")
    if data.get("version") != 1:
        raise SavedToActionError("行动数据 version 必须为 1")
    processed = data.get("processedNotes")
    actions = data.get("actions")
    if not isinstance(processed, list) or not isinstance(actions, list):
        raise SavedToActionError("processedNotes 和 actions 必须是数组")
    categories = config.get("categories", [])
    if (
        not isinstance(categories, list)
        or not categories
        or any(not isinstance(value, str) or not value.strip() for value in categories)
        or len(categories) != len(set(categories))
    ):
        raise SavedToActionError("categories 必须是非空且不重复的字符串数组")
    source_names = {
        source.get("name")
        for source in config.get("sources", [])
        if isinstance(source, dict) and isinstance(source.get("name"), str)
    }
    source_ids: set[str] = set()
    action_ids: set[str] = set()
    action_by_source: dict[str, set[str]] = {}
    action_records_by_source: dict[str, list[dict[str, Any]]] = {}
    for action in actions:
        if not isinstance(action, dict):
            raise SavedToActionError("actions 元素必须是对象")
        required = [
            "id",
            "sourceId",
            "sourceName",
            "relativePath",
            "collectionTitle",
            "category",
            "intent",
            "task",
            "savedAt",
            "sourceType",
        ]
        missing = [key for key in required if not isinstance(action.get(key), str) or not action[key]]
        if missing:
            raise SavedToActionError(f"行动字段缺失：{', '.join(missing)}")
        if action["id"] in action_ids:
            raise SavedToActionError(f"行动 id 重复：{action['id']}")
        action_ids.add(action["id"])
        if action["category"] not in categories:
            raise SavedToActionError(f"行动分类不在配置中：{action['category']}")
        if action["sourceName"] not in source_names or not safe_relative_path(action["relativePath"]):
            raise SavedToActionError("行动来源名称或相对路径无效")
        detail = action.get("detail")
        if detail is not None and not isinstance(detail, str):
            raise SavedToActionError("detail 必须是字符串或 null")
        action_by_source.setdefault(action["sourceId"], set()).add(action["id"])
        action_records_by_source.setdefault(action["sourceId"], []).append(action)
    processed_by_source: dict[str, dict[str, Any]] = {}
    for item in processed:
        if not isinstance(item, dict) or not isinstance(item.get("sourceId"), str):
            raise SavedToActionError("processedNotes 元素缺少 sourceId")
        source_id = item["sourceId"]
        if source_id in source_ids:
            raise SavedToActionError(f"processedNotes sourceId 重复：{source_id}")
        source_ids.add(source_id)
        processed_by_source[source_id] = item
        if (
            item.get("sourceName") not in source_names
            or not safe_relative_path(item.get("relativePath"))
            or not isinstance(item.get("title"), str)
            or not item["title"]
        ):
            raise SavedToActionError("processedNotes 来源名称、相对路径或标题无效")
        ids = item.get("actionIds")
        if not isinstance(ids, list) or any(not isinstance(value, str) for value in ids):
            raise SavedToActionError("processedNotes.actionIds 必须是字符串数组")
        if item.get("mode") == "incremental":
            if not 1 <= len(ids) <= 2:
                raise SavedToActionError("增量笔记必须关联 1–2 个行动")
            if set(ids) != action_by_source.get(source_id, set()):
                raise SavedToActionError("增量笔记 actionIds 与 actions 不一致")
        elif ids:
            raise SavedToActionError("基线笔记不得包含 actionIds")
    for source_id, records in action_records_by_source.items():
        item = processed_by_source.get(source_id)
        if item is None or item.get("mode") != "incremental":
            raise SavedToActionError("存在没有增量处理记录的行动")
        for action in records:
            if (
                action["sourceName"] != item["sourceName"]
                or action["relativePath"] != item["relativePath"]
                or action["collectionTitle"] != item["title"]
            ):
                raise SavedToActionError("行动与处理记录的来源引用不一致")
    if notes is not None:
        known = {note.source_id: note for note in notes}
        for item in processed:
            note = known.get(item["sourceId"])
            if note and (
                item.get("sourceName") != note.source_name
                or item.get("relativePath") != note.relative_path
            ):
                raise SavedToActionError("已处理笔记的来源路径与当前扫描结果不一致")


def action_id(source_id: str, index: int) -> str:
    digest = hashlib.sha256(source_id.encode("utf-8")).hexdigest()[:20]
    return f"action:{digest}:{index}"


def commit_batch(workspace: Path, batch_path: Path) -> dict[str, Any]:
    _, config, data_path, data = load_workspace(workspace)
    notes = scan_notes(config)
    pending = {note.source_id: note for note in pending_notes(notes, data)}
    batch = read_json(batch_path.expanduser().resolve())
    entries = batch.get("notes")
    if not isinstance(entries, list) or not entries:
        raise SavedToActionError("候选文件 notes 必须是非空数组")
    seen: set[str] = set()
    new_actions: list[dict[str, Any]] = []
    new_processed: list[dict[str, Any]] = []
    categories = config.get("categories", [])
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("sourceId"), str):
            raise SavedToActionError("候选笔记缺少 sourceId")
        source_id = entry["sourceId"]
        if source_id in seen:
            raise SavedToActionError(f"候选笔记重复：{source_id}")
        seen.add(source_id)
        note = pending.get(source_id)
        if note is None:
            raise SavedToActionError(f"候选笔记不是当前待处理项：{source_id}")
        candidates = entry.get("actions")
        if not isinstance(candidates, list) or not 1 <= len(candidates) <= 2:
            raise SavedToActionError("每篇候选笔记必须包含 1–2 个行动")
        ids: list[str] = []
        for index, candidate in enumerate(candidates, start=1):
            if not isinstance(candidate, dict):
                raise SavedToActionError("候选行动必须是对象")
            category = candidate.get("category")
            intent = candidate.get("intent")
            task = candidate.get("task")
            detail = candidate.get("detail")
            if category not in categories:
                raise SavedToActionError(f"候选分类不在配置中：{category}")
            if not isinstance(intent, str) or not intent.strip():
                raise SavedToActionError("候选 intent 不能为空")
            if not isinstance(task, str) or not task.strip():
                raise SavedToActionError("候选 task 不能为空")
            if detail is not None and not isinstance(detail, str):
                raise SavedToActionError("候选 detail 必须是字符串或 null")
            identifier = action_id(source_id, index)
            ids.append(identifier)
            new_actions.append(
                {
                    "id": identifier,
                    "sourceId": source_id,
                    "sourceName": note.source_name,
                    "relativePath": note.relative_path,
                    "collectionTitle": note.title,
                    "category": category,
                    "intent": intent.strip(),
                    "task": task.strip(),
                    "detail": detail.strip() if isinstance(detail, str) and detail.strip() else None,
                    "savedAt": note.saved_at,
                    "sourceType": "Markdown 笔记",
                }
            )
        new_processed.append(
            {
                "sourceId": source_id,
                "sourceName": note.source_name,
                "relativePath": note.relative_path,
                "title": note.title,
                "processedAt": today_iso(),
                "mode": "incremental",
                "actionIds": ids,
            }
        )
    candidate_data = {
        **data,
        "updatedAt": now_iso(),
        "processedNotes": [*data.get("processedNotes", []), *new_processed],
        "actions": [*data.get("actions", []), *new_actions],
    }
    validate_data(config, candidate_data, notes)
    atomic_write_json(data_path, candidate_data)
    return {
        "processedCount": len(new_processed),
        "actionCount": len(new_actions),
        "titles": [item["title"] for item in new_processed],
        "dataPath": str(data_path),
    }


def app_support_path() -> Path:
    return Path.home() / "Library" / "Application Support" / "SavedToAction" / "app.json"


def configure_app(workspace: Path, output: Path | None = None) -> dict[str, Any]:
    workspace, _, _, _ = load_workspace(workspace)
    target = output.expanduser().resolve() if output is not None else app_support_path()
    atomic_write_json(target, {"version": 1, "workspaceConfigPath": str(workspace / CONFIG_NAME)})
    return {"appConfigPath": str(target), "workspace": str(workspace)}


def inspect_sources(sources: list[dict[str, str]], limit: int) -> dict[str, Any]:
    config = {
        "sources": sources,
        "recursive": True,
        "include": ["**/*.md"],
        "exclude": DEFAULT_EXCLUDES,
        "identityKeys": ["uid", "id"],
    }
    notes = scan_notes(config)
    return {
        "sourceCount": len(sources),
        "notesFound": len(notes),
        "identitySummary": {
            "frontmatter": sum(note.identity_kind.startswith("frontmatter:") for note in notes),
            "relativePath": sum(note.identity_kind == "relative-path" for note in notes),
        },
        "examples": [note.public_dict() for note in notes[-max(0, limit) :]],
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Saved to Action workspace tool")
    subparsers = parser.add_subparsers(dest="command", required=True)

    inspect_parser = subparsers.add_parser("inspect", help="只读检查 Markdown 来源")
    inspect_parser.add_argument("--source", action="append", required=True, metavar="NAME=PATH")
    inspect_parser.add_argument("--limit", type=int, default=5)

    init_parser = subparsers.add_parser("init", help="初始化工作目录")
    init_parser.add_argument("--workspace", required=True)
    init_parser.add_argument("--source", action="append", required=True, metavar="NAME=PATH")
    init_parser.add_argument("--mode", choices=["future", "latest", "all"], required=True)
    init_parser.add_argument("--latest", type=int, default=10)
    init_parser.add_argument("--category", action="append", help="自定义分类；可重复传入")

    discover_parser = subparsers.add_parser("discover", help="列出尚未处理的笔记")
    discover_parser.add_argument("--workspace", required=True)
    discover_parser.add_argument("--limit", type=int, default=0)

    commit_parser = subparsers.add_parser("commit", help="验证并原子提交候选行动")
    commit_parser.add_argument("--workspace", required=True)
    commit_parser.add_argument("--input", required=True)

    validate_parser = subparsers.add_parser("validate", help="验证配置和行动数据")
    validate_parser.add_argument("--workspace", required=True)

    app_parser = subparsers.add_parser("configure-app", help="写入本机 App 工作区指针")
    app_parser.add_argument("--workspace", required=True)
    app_parser.add_argument("--output", help="将 App 指针写入指定文件；省略时写入用户 Application Support")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "inspect":
            result = inspect_sources([parse_source_argument(value) for value in args.source], args.limit)
        elif args.command == "init":
            result = initialize_workspace(
                Path(args.workspace),
                [parse_source_argument(value) for value in args.source],
                args.mode,
                args.latest,
                args.category,
            )
        elif args.command == "discover":
            _, config, _, data = load_workspace(Path(args.workspace))
            pending = pending_notes(scan_notes(config), data)
            if args.limit > 0:
                pending = pending[: args.limit]
            result = {"pendingCount": len(pending), "notes": [note.public_dict() for note in pending]}
        elif args.command == "commit":
            result = commit_batch(Path(args.workspace), Path(args.input))
        elif args.command == "validate":
            _, config, data_path, data = load_workspace(Path(args.workspace))
            notes = scan_notes(config)
            validate_data(config, data, notes)
            result = {
                "valid": True,
                "dataPath": str(data_path),
                "processedCount": len(data["processedNotes"]),
                "actionCount": len(data["actions"]),
                "pendingCount": len(pending_notes(notes, data)),
            }
        elif args.command == "configure-app":
            result = configure_app(Path(args.workspace), Path(args.output) if args.output else None)
        else:
            raise SavedToActionError(f"不支持的命令：{args.command}")
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except SavedToActionError as exc:
        print(json.dumps({"error": str(exc)}, ensure_ascii=False, indent=2), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
