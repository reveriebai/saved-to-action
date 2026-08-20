#!/usr/bin/env python3
"""Read-only source adapters for Markdown-adjacent Saved to Action inputs."""

from __future__ import annotations

import datetime as dt
import gzip
import json
import os
import shutil
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import zlib
from html import unescape
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Callable, Iterable


IMA_BASE_URL = "https://ima.qq.com"
WECHAT_USER_AGENT = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
    "AppleWebKit/605.1.15 Mobile/15E148 "
    "MicroMessenger/8.0.56 NetType/WIFI Language/zh_CN"
)
BLOCKED_WECHAT_MARKERS = ("环境异常", "完成验证后即可继续访问", "去验证")


class SourceAdapterError(RuntimeError):
    pass


def source_kind(source: dict[str, Any]) -> str:
    kind = source.get("kind", "markdown")
    return kind if isinstance(kind, str) else ""


def _run_getnote(arguments: list[str]) -> str:
    binary = shutil.which("getnote")
    if not binary:
        raise SourceAdapterError("未找到 getnote CLI；请先安装并登录 Get笔记 skill")
    try:
        result = subprocess.run(
            [binary, *arguments],
            check=False,
            capture_output=True,
            text=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired as exc:
        raise SourceAdapterError("Get笔记读取超时") from exc
    if result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip() or "Get笔记命令失败"
        raise SourceAdapterError(message)
    return result.stdout


def check_getnote_auth() -> None:
    output = _run_getnote(["auth", "status"])
    if "Authenticated" not in output:
        raise SourceAdapterError("Get笔记尚未登录；请先运行 getnote auth login")


def _json_documents(text: str) -> list[Any]:
    stripped = text.strip()
    if not stripped:
        raise SourceAdapterError("来源返回了空 JSON")
    try:
        return [json.loads(stripped)]
    except json.JSONDecodeError:
        documents: list[Any] = []
        for line in stripped.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                documents.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise SourceAdapterError("来源返回的 JSON 无法解析") from exc
        if not documents:
            raise SourceAdapterError("来源返回的 JSON 无法解析")
        return documents


def _collect_key(documents: Iterable[Any], key: str) -> list[dict[str, Any]]:
    collected: list[dict[str, Any]] = []
    for document in documents:
        if isinstance(document, list):
            collected.extend(item for item in document if isinstance(item, dict))
            continue
        if not isinstance(document, dict):
            continue
        data = document.get("data", document)
        if isinstance(data, dict) and isinstance(data.get(key), list):
            collected.extend(item for item in data[key] if isinstance(item, dict))
    return collected


def list_getnote_knowledge_bases() -> list[dict[str, str]]:
    check_getnote_auth()
    results: list[dict[str, str]] = []
    seen: set[str] = set()
    for command, ownership in ((["kbs", "-o", "json"], "owned"), (["kbs-sub", "-o", "json"], "subscribed")):
        for topic in _collect_key(_json_documents(_run_getnote(command)), "topics"):
            topic_id = str(topic.get("topic_id") or "")
            name = str(topic.get("name") or "")
            if not topic_id or not name or topic_id in seen:
                continue
            seen.add(topic_id)
            results.append({"id": topic_id, "name": name, "ownership": ownership})
    return results


def _date_from_value(value: Any) -> str:
    if isinstance(value, (int, float)):
        seconds = float(value) / 1000 if value > 10_000_000_000 else float(value)
        return dt.datetime.fromtimestamp(seconds).date().isoformat()
    if isinstance(value, str) and value.strip():
        candidate = value.strip()
        if candidate.isdigit():
            return _date_from_value(int(candidate))
        try:
            return dt.datetime.fromisoformat(candidate.replace("Z", "+00:00")).date().isoformat()
        except ValueError:
            if len(candidate) >= 10:
                try:
                    return dt.date.fromisoformat(candidate[:10]).isoformat()
                except ValueError:
                    pass
    return dt.date.today().isoformat()


def _getnote_type(note_type: str) -> str:
    if note_type == "link":
        return "Get笔记网页收藏"
    if note_type in {"audio", "meeting", "local_audio", "internal_record", "class_audio", "recorder_audio", "recorder_flash_audio"}:
        return "Get笔记录音"
    return "Get笔记"


def list_getnote_notes(source: dict[str, Any]) -> list[dict[str, Any]]:
    check_getnote_auth()
    topic_id = source.get("topicId")
    if isinstance(topic_id, str) and topic_id:
        arguments = ["kb", topic_id, "--all", "-o", "json"]
    else:
        arguments = ["notes", "--all", "-o", "json"]
    notes = _collect_key(_json_documents(_run_getnote(arguments)), "notes")
    records: list[dict[str, Any]] = []
    for position, note in enumerate(notes):
        note_id = str(note.get("note_id") or note.get("id") or "")
        if not note_id:
            continue
        note_type = str(note.get("note_type") or "")
        records.append(
            {
                "externalId": note_id,
                "relativePath": f"notes/{urllib.parse.quote(note_id, safe='')}",
                "title": str(note.get("title") or "未命名 Get笔记"),
                "savedAt": _date_from_value(note.get("created_at") or note.get("createdAt")),
                "modifiedAt": -float(position),
                "sourceType": _getnote_type(note_type),
                "mediaType": note_type,
            }
        )
    return records


def _https_url(value: Any) -> str | None:
    if not isinstance(value, str) or not value:
        return None
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme.lower() != "https" or not parsed.hostname or parsed.username or parsed.password:
        return None
    return urllib.parse.urlunparse(parsed._replace(fragment=""))


def read_getnote_note(external_id: str) -> dict[str, Any]:
    check_getnote_auth()
    documents = _json_documents(_run_getnote(["note", external_id, "-o", "json"]))
    document = documents[0] if documents else {}
    data = document.get("data", document) if isinstance(document, dict) else {}
    note = data.get("note", data) if isinstance(data, dict) else {}
    if not isinstance(note, dict):
        raise SourceAdapterError("Get笔记正文结构无效")
    note_type = str(note.get("note_type") or "")
    web_page = note.get("web_page") if isinstance(note.get("web_page"), dict) else {}
    if note_type == "link":
        content = web_page.get("content") or note.get("web_content") or note.get("content")
    elif note_type in {"audio", "meeting", "local_audio", "internal_record", "class_audio", "recorder_audio", "recorder_flash_audio"}:
        content = note.get("audio_original") or note.get("content")
    else:
        content = note.get("content")
    if not isinstance(content, str) or not content.strip():
        raise SourceAdapterError("Get笔记没有可用于提炼的正文")
    source_url = canonicalize_source_url(web_page.get("url") or note.get("url"))
    if source_url is None and isinstance(note.get("attachments"), list):
        for attachment in note["attachments"]:
            if isinstance(attachment, dict):
                source_url = canonicalize_source_url(attachment.get("url"))
                if source_url:
                    break
    return {
        "content": content.strip(),
        "sourceURL": source_url,
        "savedAt": _date_from_value(note.get("created_at") or note.get("createdAt")),
        "sourceType": _getnote_type(note_type),
    }


def _ima_credentials() -> tuple[str, str]:
    config = Path.home() / ".config" / "ima"
    client_id = (
        os.environ.get("IMA_CLIENT_ID")
        or os.environ.get("IMA_OPENAPI_CLIENTID")
        or _read_optional(config / "client_id")
    )
    api_key = (
        os.environ.get("IMA_API_KEY")
        or os.environ.get("IMA_OPENAPI_APIKEY")
        or _read_optional(config / "api_key")
    )
    if not client_id or not api_key:
        raise SourceAdapterError("未找到 IMA OpenAPI 凭证")
    return client_id, api_key


def _read_optional(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def _decode_response(response: Any, payload: bytes) -> bytes:
    encoding = str(response.headers.get("Content-Encoding", "")).lower()
    if encoding == "gzip":
        return gzip.decompress(payload)
    if encoding == "deflate":
        return zlib.decompress(payload)
    return payload


def _open(request: urllib.request.Request, timeout: int = 60) -> tuple[Any, bytes]:
    try:
        response = urllib.request.urlopen(request, timeout=timeout)
        payload = response.read()
        return response, _decode_response(response, payload)
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise SourceAdapterError(f"网络读取失败：{exc}") from exc


def ima_api(api_path: str, body: dict[str, Any]) -> dict[str, Any]:
    client_id, api_key = _ima_credentials()
    request = urllib.request.Request(
        f"{IMA_BASE_URL}/{api_path}",
        data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
        method="POST",
        headers={
            "ima-openapi-clientid": client_id,
            "ima-openapi-apikey": api_key,
            "Content-Type": "application/json",
        },
    )
    _, payload = _open(request)
    try:
        parsed = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SourceAdapterError("IMA 返回的 JSON 无法解析") from exc
    if not isinstance(parsed, dict) or parsed.get("code") != 0:
        message = parsed.get("msg") if isinstance(parsed, dict) else "IMA 请求失败"
        raise SourceAdapterError(str(message or "IMA 请求失败"))
    data = parsed.get("data", {})
    return data if isinstance(data, dict) else {}


def list_ima_knowledge_bases() -> list[dict[str, str]]:
    cursor = ""
    results: list[dict[str, str]] = []
    while True:
        data = ima_api(
            "openapi/wiki/v1/search_knowledge_base",
            {"query": "", "cursor": cursor, "limit": 20},
        )
        for item in data.get("info_list", []):
            if not isinstance(item, dict):
                continue
            identifier = str(item.get("kb_id") or item.get("id") or "")
            name = str(item.get("kb_name") or item.get("name") or "")
            if identifier and name:
                results.append({"id": identifier, "name": name})
        if data.get("is_end", True):
            break
        cursor = str(data.get("next_cursor") or "")
        if not cursor:
            break
    return results


def _ima_type(media_type: int) -> str:
    return {
        2: "IMA 网页收藏",
        6: "IMA 公众号文章",
        7: "IMA Markdown",
        9: "IMA 文本",
        11: "IMA 原生笔记",
    }.get(media_type, "IMA 文件")


def list_ima_items(source: dict[str, Any]) -> list[dict[str, Any]]:
    knowledge_base_id = source.get("knowledgeBaseId")
    if not isinstance(knowledge_base_id, str) or not knowledge_base_id:
        raise SourceAdapterError("IMA 来源缺少 knowledgeBaseId")
    folders: list[str | None] = [None]
    records: list[dict[str, Any]] = []
    position = 0
    while folders:
        folder_id = folders.pop(0)
        cursor = ""
        while True:
            body: dict[str, Any] = {
                "knowledge_base_id": knowledge_base_id,
                "cursor": cursor,
                "limit": 50,
            }
            if folder_id:
                body["folder_id"] = folder_id
            data = ima_api("openapi/wiki/v1/get_knowledge_list", body)
            for item in data.get("knowledge_list", []):
                if not isinstance(item, dict):
                    continue
                media_id = str(item.get("media_id") or item.get("folder_id") or "")
                if not media_id:
                    continue
                if media_id.startswith("folder_"):
                    folders.append(media_id)
                    continue
                try:
                    media_type = int(item.get("media_type", 0))
                except (TypeError, ValueError):
                    media_type = 0
                records.append(
                    {
                        "externalId": media_id,
                        "relativePath": f"media/{urllib.parse.quote(media_id, safe='')}",
                        "title": str(item.get("title") or "未命名 IMA 条目"),
                        "savedAt": dt.date.today().isoformat(),
                        "modifiedAt": -float(position),
                        "sourceType": _ima_type(media_type),
                        "mediaType": media_type,
                    }
                )
                position += 1
            if data.get("is_end", True):
                break
            cursor = str(data.get("next_cursor") or "")
            if not cursor:
                break
    return records


class _TextExtractor(HTMLParser):
    def __init__(self, target_id: str | None = None) -> None:
        super().__init__(convert_charrefs=True)
        self.target_id = target_id
        self.active = target_id is None
        self.target_depth = 0
        self.skip_depth = 0
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        if tag in {"script", "style"}:
            self.skip_depth += 1
            return
        if self.target_id and not self.active and attributes.get("id") == self.target_id:
            self.active = True
            self.target_depth = 1
        elif self.active and self.target_id:
            self.target_depth += 1
        if self.active and tag in {"br", "p", "section", "li", "h1", "h2", "h3", "blockquote"}:
            self.parts.append("\n")

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if self.active and tag == "br":
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag in {"script", "style"} and self.skip_depth:
            self.skip_depth -= 1
            return
        if self.active and self.target_id:
            self.target_depth -= 1
            if self.target_depth <= 0:
                self.active = False
        if self.active and tag in {"p", "section", "li", "h1", "h2", "h3", "blockquote"}:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        if self.active and not self.skip_depth:
            self.parts.append(data)

    def text(self) -> str:
        lines = [" ".join(line.split()) for line in unescape("".join(self.parts)).splitlines()]
        return "\n".join(line for line in lines if line).strip()


def _html_text(html: str, target_id: str | None = None) -> str:
    parser = _TextExtractor(target_id)
    parser.feed(html)
    return parser.text()


def canonicalize_source_url(value: Any) -> str | None:
    safe = _https_url(value)
    if safe is None:
        return None
    parsed = urllib.parse.urlparse(safe)
    host = (parsed.hostname or "").lower()
    if host == "mp.weixin.qq.com":
        query = urllib.parse.parse_qs(parsed.query, keep_blank_values=False)
        retained = []
        for key in ("__biz", "mid", "idx", "sn"):
            if query.get(key):
                retained.append((key, query[key][0]))
        if not retained:
            return "https://mp.weixin.qq.com/"
        return urllib.parse.urlunparse(parsed._replace(query=urllib.parse.urlencode(retained), fragment=""))
    if host.endswith(".myqcloud.com"):
        return None
    query_keys = {key.lower() for key in urllib.parse.parse_qs(parsed.query)}
    if query_keys & {"expires", "signature", "token", "sessionid", "pass_ticket", "authkey"}:
        return None
    return safe


def _read_remote_text(url: str, supplied_headers: dict[str, Any]) -> tuple[str, str | None]:
    safe_url = _https_url(url)
    if safe_url is None:
        raise SourceAdapterError("IMA 返回了不安全的原文地址")
    headers = {str(key): str(value) for key, value in supplied_headers.items()}
    lower_keys = {key.lower() for key in headers}
    host = (urllib.parse.urlparse(safe_url).hostname or "").lower()
    if host == "mp.weixin.qq.com" and "user-agent" not in lower_keys:
        headers["User-Agent"] = WECHAT_USER_AGENT
    if "accept-encoding" not in lower_keys:
        headers["Accept-Encoding"] = "gzip, deflate"
    headers.setdefault("Accept", "text/html,application/xhtml+xml,text/plain")
    response, payload = _open(urllib.request.Request(safe_url, headers=headers), timeout=90)
    content_type = str(response.headers.get("Content-Type", "")).lower()
    charset = response.headers.get_content_charset() if hasattr(response.headers, "get_content_charset") else None
    text = payload.decode(charset or "utf-8", errors="replace")
    if host == "mp.weixin.qq.com":
        blocked = any(marker in text for marker in BLOCKED_WECHAT_MARKERS)
        if blocked or len(payload) < 50_000 or "js_content" not in text:
            raise SourceAdapterError("微信公众号返回验证页而非正文")
        content = _html_text(text, "js_content")
    elif "html" in content_type or "<html" in text[:1000].lower():
        content = _html_text(text)
    elif any(value in content_type for value in ("text/", "json", "markdown")):
        content = text.strip()
    else:
        raise SourceAdapterError("该 IMA 文件不是可直接提炼的文本；请改用原生笔记、网页或文本文件")
    if not content:
        raise SourceAdapterError("IMA 原文正文为空")
    return content, canonicalize_source_url(safe_url)


def read_ima_item(external_id: str, media_type: int) -> dict[str, Any]:
    last_error: SourceAdapterError | None = None
    for _ in range(2):
        info = ima_api("openapi/wiki/v1/get_media_info", {"media_id": external_id})
        actual_type = int(info.get("media_type", media_type) or 0)
        notebook = info.get("notebook_ext_info")
        if actual_type == 11 and isinstance(notebook, dict) and notebook.get("notebook_id"):
            data = ima_api(
                "openapi/note/v1/get_doc_content",
                {"note_id": str(notebook["notebook_id"]), "target_content_format": 0},
            )
            content = data.get("content")
            if not isinstance(content, str) or not content.strip():
                raise SourceAdapterError("IMA 原生笔记正文为空")
            return {
                "content": content.strip(),
                "sourceURL": None,
                "savedAt": dt.date.today().isoformat(),
                "sourceType": _ima_type(actual_type),
            }
        url_info = info.get("url_info")
        if not isinstance(url_info, dict) or not isinstance(url_info.get("url"), str):
            raise SourceAdapterError("IMA 没有提供可读取的原文入口")
        try:
            content, source_url = _read_remote_text(
                url_info["url"],
                url_info.get("headers") if isinstance(url_info.get("headers"), dict) else {},
            )
            return {
                "content": content,
                "sourceURL": source_url,
                "savedAt": dt.date.today().isoformat(),
                "sourceType": _ima_type(actual_type),
            }
        except SourceAdapterError as exc:
            last_error = exc
    raise last_error or SourceAdapterError("IMA 原文读取失败")
