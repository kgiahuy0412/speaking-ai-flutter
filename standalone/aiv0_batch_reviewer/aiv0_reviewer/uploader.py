from __future__ import annotations

import json
import mimetypes
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from .models import AudioRecord


@dataclass(slots=True)
class UploadConfig:
    endpoint: str
    token: str = ""
    file_field: str = "file"
    id_json_path: str = "audio_id"
    timeout_seconds: int = 60


@dataclass(slots=True)
class UploadResult:
    audio_id: str
    response: dict[str, Any]


def extract_json_path(payload: dict[str, Any], path: str) -> Any:
    value: Any = payload
    for part in path.split("."):
        if not isinstance(value, dict) or part not in value:
            return None
        value = value[part]
    return value


def _multipart_body(record: AudioRecord, audio_path: Path, file_field: str) -> tuple[bytes, str]:
    boundary = f"----AIV0{uuid.uuid4().hex}"
    chunks: list[bytes] = []

    def add_field(name: str, value: str) -> None:
        chunks.extend(
            [
                f"--{boundary}\r\n".encode(),
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(),
                value.encode("utf-8"),
                b"\r\n",
            ]
        )

    add_field("record_id", record.record_id)
    add_field("batch_id", record.batch_id)
    add_field("sentence_code", record.sentence_code)
    mime = mimetypes.guess_type(audio_path.name)[0] or "application/octet-stream"
    chunks.extend(
        [
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="{file_field}"; filename="{audio_path.name}"\r\n'.encode(),
            f"Content-Type: {mime}\r\n\r\n".encode(),
            audio_path.read_bytes(),
            b"\r\n",
            f"--{boundary}--\r\n".encode(),
        ]
    )
    return b"".join(chunks), boundary


def upload_audio(record: AudioRecord, config: UploadConfig) -> UploadResult:
    if not config.endpoint.strip():
        raise ValueError("Chưa cấu hình API endpoint.")
    audio_path = Path(record.local_audio_path)
    if not audio_path.is_file():
        raise ValueError(f"Không tìm thấy audio cục bộ cho {record.record_id}.")

    body, boundary = _multipart_body(record, audio_path, config.file_field or "file")
    headers = {
        "Content-Type": f"multipart/form-data; boundary={boundary}",
        "Accept": "application/json",
        "User-Agent": "AIV0-Batch-Audio-Manager/0.1",
    }
    if config.token:
        headers["Authorization"] = f"Bearer {config.token}"
    request = Request(config.endpoint, data=body, headers=headers, method="POST")
    try:
        with urlopen(request, timeout=config.timeout_seconds) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"API trả về HTTP {error.code}: {detail[:300]}") from error
    except URLError as error:
        raise RuntimeError(f"Không kết nối được API: {error.reason}") from error
    except json.JSONDecodeError as error:
        raise RuntimeError("API không trả về JSON hợp lệ.") from error

    audio_id = extract_json_path(payload, config.id_json_path)
    if audio_id in (None, ""):
        for fallback in ("audio_id", "id", "data.audio_id", "data.id"):
            audio_id = extract_json_path(payload, fallback)
            if audio_id not in (None, ""):
                break
    if audio_id in (None, ""):
        raise RuntimeError(f"Không tìm thấy ID trong phản hồi API. JSON path: {config.id_json_path}")
    return UploadResult(str(audio_id), payload)

