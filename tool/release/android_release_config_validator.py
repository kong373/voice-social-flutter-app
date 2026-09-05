#!/usr/bin/env python3
"""Fail-closed validator for the public Android release Dart defines file."""

from __future__ import annotations

import ipaddress
import json
import os
import re
import stat
import sys
import tempfile
from urllib.parse import urlsplit


MAX_CONFIG_BYTES = 64 * 1024
MAX_ROOT_FIELDS = 32

ALLOWED_FIELDS = frozenset(
    {
        "APP_ENV",
        "BACKEND_MODE",
        "API_BASE_URL",
        "OAUTH_CLIENT_ID",
        "CLIENT_TYPE",
        "CLIENT_INNER_VERSION",
        "API_TIMEOUT_SECONDS",
        "ROOM_REALTIME_ENDPOINT",
        "LIVE_PROBE_PATH",
        "ALLOW_INSECURE_HTTP",
        "ENABLE_AGORA_RTC",
        "ENABLE_ALIPAY_APP_PAY",
        "ALIPAY_FORMAL_ACCEPTANCE",
        "ENABLE_APPLE_IAP",
        "ENABLE_TENCENT_IM",
    }
)
BOOLEAN_FIELDS = frozenset(
    {
        "ALLOW_INSECURE_HTTP",
        "ENABLE_AGORA_RTC",
        "ENABLE_ALIPAY_APP_PAY",
        "ALIPAY_FORMAL_ACCEPTANCE",
        "ENABLE_APPLE_IAP",
        "ENABLE_TENCENT_IM",
    }
)
FALSE_ONLY_FIELDS = frozenset(
    {
        "ALLOW_INSECURE_HTTP",
        "ALIPAY_FORMAL_ACCEPTANCE",
        "ENABLE_APPLE_IAP",
    }
)
OAUTH_SECRET_LIKE = re.compile(
    r"(^|[^a-z0-9])"
    r"(oauth[-_.:/+]?client[-_.:/+]?secret|client[-_.:/+]?secret|"
    r"secret|password|private[-_.:/+]?key|access[-_.:/+]?key|"
    r"api[-_.:/+]?key|token|credential|credentials|pat|auth|bearer)"
    r"([^a-z0-9]|$)"
)
HOSTNAME = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$")


class ConfigError(Exception):
    """A safe, value-free validation error."""

    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def _object_pairs_without_duplicates(
    pairs: list[tuple[str, object]],
) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ConfigError("duplicate_key")
        result[key] = value
    return result


def _read_json_file(path_value: str) -> dict[str, object]:
    if not os.path.isabs(path_value):
        raise ConfigError("config_path_not_absolute")
    if "\x00" in path_value:
        raise ConfigError("config_path_invalid")

    try:
        path_stat = os.lstat(path_value)
    except FileNotFoundError as error:
        raise ConfigError("config_missing") from error
    except OSError as error:
        raise ConfigError("config_unreadable") from error

    if stat.S_ISLNK(path_stat.st_mode):
        raise ConfigError("config_symlink")
    if not stat.S_ISREG(path_stat.st_mode):
        raise ConfigError("config_not_regular")
    if path_stat.st_size > MAX_CONFIG_BYTES:
        raise ConfigError("config_too_large")

    open_flags = os.O_RDONLY
    open_flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        file_descriptor = os.open(path_value, open_flags)
        with os.fdopen(file_descriptor, "rb") as config_file:
            raw_config = config_file.read(MAX_CONFIG_BYTES + 1)
    except OSError as error:
        raise ConfigError("config_unreadable") from error

    if len(raw_config) > MAX_CONFIG_BYTES:
        raise ConfigError("config_too_large")
    try:
        source = raw_config.decode("utf-8")
        decoded = json.loads(
            source,
            object_pairs_hook=_object_pairs_without_duplicates,
        )
    except ConfigError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError, TypeError) as error:
        raise ConfigError("invalid_json") from error

    if not isinstance(decoded, dict):
        raise ConfigError("root_not_object")
    return decoded


def _require_text(config: dict[str, object], field: str) -> str:
    value = config.get(field)
    if not isinstance(value, str) or not value:
        raise ConfigError("field_invalid")
    return value


def _optional_text(config: dict[str, object], field: str) -> str | None:
    if field not in config:
        return None
    value = config[field]
    if not isinstance(value, str):
        raise ConfigError("field_invalid")
    return value


def _validate_api_origin(value: str) -> None:
    if value != value.strip() or any(
        character.isspace() or ord(character) < 0x21 or ord(character) == 0x7F
        for character in value
    ):
        raise ConfigError("api_base_url_invalid")

    try:
        parsed = urlsplit(value)
        hostname = parsed.hostname
        port = parsed.port
    except ValueError as error:
        raise ConfigError("api_base_url_invalid") from error

    if (
        parsed.scheme.lower() != "https"
        or not parsed.netloc
        or not hostname
        or "@" in parsed.netloc
        or parsed.username is not None
        or parsed.password is not None
        or "?" in value
        or "#" in value
        or parsed.path not in ("", "/")
        or not _is_valid_hostname(hostname)
        or (port is not None and not 1 <= port <= 65535)
    ):
        raise ConfigError("api_base_url_invalid")


def _is_valid_hostname(hostname: str) -> bool:
    if ":" in hostname:
        try:
            return ipaddress.ip_address(hostname).version == 6
        except ValueError:
            return False
    return HOSTNAME.fullmatch(hostname) is not None


def _validate_public_client_id(value: str) -> None:
    if not 1 <= len(value) <= 256:
        raise ConfigError("oauth_client_id_invalid")
    if any(
        character.isspace()
        or character == "="
        or not 0x21 <= ord(character) <= 0x7E
        for character in value
    ):
        raise ConfigError("oauth_client_id_invalid")
    if OAUTH_SECRET_LIKE.search(value.lower()):
        raise ConfigError("oauth_client_id_invalid")


def _read_bool(config: dict[str, object], field: str) -> bool:
    if field not in config:
        return False
    value = config[field]
    if isinstance(value, bool):
        return value
    if isinstance(value, str) and value in ("true", "false"):
        return value == "true"
    raise ConfigError("boolean_invalid")


def _validate_optional_numeric_fields(config: dict[str, object]) -> None:
    if "CLIENT_INNER_VERSION" in config:
        value = _optional_text(config, "CLIENT_INNER_VERSION")
        if value is None or not re.fullmatch(r"[1-9][0-9]*", value):
            raise ConfigError("client_inner_version_invalid")

    if "API_TIMEOUT_SECONDS" in config:
        value = config["API_TIMEOUT_SECONDS"]
        if isinstance(value, bool):
            raise ConfigError("api_timeout_invalid")
        if isinstance(value, int):
            timeout = value
        elif isinstance(value, str) and re.fullmatch(r"[0-9]+", value):
            timeout = int(value)
        else:
            raise ConfigError("api_timeout_invalid")
        if not 5 <= timeout <= 60:
            raise ConfigError("api_timeout_invalid")


def validate_config(config: dict[str, object]) -> None:
    if not config or len(config) > MAX_ROOT_FIELDS:
        raise ConfigError("root_fields_invalid")
    if any(field not in ALLOWED_FIELDS for field in config):
        raise ConfigError("unknown_field")

    if _require_text(config, "APP_ENV") not in ("staging", "production"):
        raise ConfigError("app_env_invalid")
    if _require_text(config, "BACKEND_MODE") != "live":
        raise ConfigError("backend_mode_invalid")
    if _require_text(config, "CLIENT_TYPE") != "Android":
        raise ConfigError("client_type_invalid")

    _validate_api_origin(_require_text(config, "API_BASE_URL"))
    _validate_public_client_id(_require_text(config, "OAUTH_CLIENT_ID"))

    for field in ("ROOM_REALTIME_ENDPOINT", "LIVE_PROBE_PATH"):
        _optional_text(config, field)
    live_probe_path = config.get("LIVE_PROBE_PATH")
    if live_probe_path is not None and (
        not isinstance(live_probe_path, str)
        or not live_probe_path.startswith("/")
        or live_probe_path.startswith("//")
    ):
        raise ConfigError("live_probe_path_invalid")
    _validate_optional_numeric_fields(config)

    for field in BOOLEAN_FIELDS:
        if _read_bool(config, field) and field in FALSE_ONLY_FIELDS:
            raise ConfigError("boolean_forbidden")


def _write_canonical_snapshot(
    path_value: str,
    config: dict[str, object],
) -> None:
    if not os.path.isabs(path_value) or "\x00" in path_value:
        raise ConfigError("snapshot_path_invalid")

    try:
        canonical = (
            json.dumps(
                config,
                ensure_ascii=False,
                allow_nan=False,
                sort_keys=True,
                separators=(",", ":"),
            )
            + "\n"
        ).encode("utf-8")
    except (TypeError, UnicodeError, ValueError) as error:
        raise ConfigError("snapshot_invalid") from error

    file_descriptor = -1
    try:
        file_descriptor = os.open(
            path_value,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
            0o600,
        )
        os.fchmod(file_descriptor, 0o600)
        with os.fdopen(file_descriptor, "wb") as snapshot_file:
            file_descriptor = -1
            snapshot_file.write(canonical)
            snapshot_file.flush()
            os.fsync(snapshot_file.fileno())
    except FileExistsError as error:
        raise ConfigError("snapshot_exists") from error
    except OSError as error:
        raise ConfigError("snapshot_write_failed") from error
    finally:
        if file_descriptor != -1:
            os.close(file_descriptor)


def validate_config_file(
    path_value: str,
    snapshot_path: str | None = None,
) -> None:
    # Keep the parsed object in memory: validation and snapshot creation must
    # operate on this one read, never on a second read of the public path.
    config = _read_json_file(path_value)
    validate_config(config)
    if snapshot_path is not None:
        _write_canonical_snapshot(snapshot_path, config)


def _self_test() -> None:
    valid = {
        "APP_ENV": "staging",
        "BACKEND_MODE": "live",
        "API_BASE_URL": "https://public.example.test/",
        "OAUTH_CLIENT_ID": "voice-social-mobile-public",
        "CLIENT_TYPE": "Android",
        "API_TIMEOUT_SECONDS": 15,
        "LIVE_PROBE_PATH": "/",
        "ALLOW_INSECURE_HTTP": False,
        "ALIPAY_FORMAL_ACCEPTANCE": False,
        "ENABLE_APPLE_IAP": False,
    }
    validate_config(valid)
    for invalid in (
        {**valid, "APP_ENV": "development"},
        {**valid, "API_BASE_URL": "http://public.example.test/"},
        {**valid, "OAUTH_CLIENT_SECRET": "not-allowed"},
        {**valid, "ENABLE_APPLE_IAP": True},
        {**valid, "LIVE_PROBE_PATH": "//attacker.example/health"},
    ):
        try:
            validate_config(invalid)
        except ConfigError:
            continue
        raise RuntimeError("self-test accepted an invalid config")

    with tempfile.TemporaryDirectory(prefix="android-release-config-") as temp_dir:
        config_path = os.path.join(temp_dir, "config.json")
        snapshot_path = os.path.join(temp_dir, "snapshot.json")
        with open(config_path, "w", encoding="utf-8") as config_file:
            json.dump(valid, config_file)
        validate_config_file(config_path, snapshot_path)
        snapshot_stat = os.stat(snapshot_path)
        if stat.S_IMODE(snapshot_stat.st_mode) != 0o600:
            raise RuntimeError("self-test snapshot mode is not 0600")
        with open(snapshot_path, "rb") as snapshot_file:
            if json.loads(snapshot_file.read()) != valid:
                raise RuntimeError("self-test snapshot content mismatch")
        try:
            _write_canonical_snapshot(snapshot_path, valid)
        except ConfigError as error:
            if error.code != "snapshot_exists":
                raise RuntimeError("self-test did not reject snapshot overwrite")
        else:
            raise RuntimeError("self-test accepted snapshot overwrite")


def main(argv: list[str]) -> int:
    if argv == ["--self-test"]:
        _self_test()
        print("android-release-config-validator=self-test-PASS")
        return 0
    if (
        len(argv) != 4
        or argv[0] != "--config-file"
        or argv[2] != "--snapshot-file"
    ):
        print("android-release-config=FAIL reason=usage", file=sys.stderr)
        return 1

    try:
        validate_config_file(argv[1], argv[3])
    except ConfigError as error:
        print(
            f"android-release-config=FAIL reason={error.code}",
            file=sys.stderr,
        )
        return 1
    print("android-release-config=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
