#!/usr/bin/env python3
"""Provider-free tests for the M5 development finance fixture utility."""

from __future__ import annotations

import hashlib
import io
import json
import os
from pathlib import Path
import socket
import stat
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch

from m5_alipay_dev_finance_fixture import (
    AuthSession,
    Challenge,
    FIXTURE_ID_RE,
    FinanceFixtureConfig,
    FinanceFixtureError,
    FirstPartyApi,
    MysqlExecutor,
    ROLE_FINANCE_APPROVER,
    ROLE_FINANCE_EXECUTOR,
    ROLE_USER,
    SCHEMA_VERSION,
    SMS_REAUTHENTICATION_WAIT_SECONDS,
    STATE_KEYS,
    _docker_environment,
    _fixture_nickname,
    _self_test,
    build_state,
    main,
    prepare_state_target,
    read_config,
    run_flow,
    validate_base_url,
    validate_development_mysql_container,
    validate_phone_triplet,
    write_state,
)


class FakeApi:
    """Minimal first-party auth double; no provider or retry behavior."""

    def __init__(self) -> None:
        self.send_calls: list[tuple[str, str]] = []
        self.register_calls: list[str] = []
        self.register_nicknames: list[str] = []
        self.login_calls: list[str] = []
        self._ids = {
            "13900000001": 101,
            "13900000002": 202,
            "13900000003": 303,
        }
        self._roles = {101: ROLE_USER, 202: ROLE_USER, 303: ROLE_USER}
        self.wrong_reviewer_role = False

    def send_code(self, phone: str, device_id: str) -> Challenge:
        self.send_calls.append((phone, device_id))
        return Challenge("challenge-" + str(len(self.send_calls)), "123456")

    def register(self, phone: str, code: str, device_id: str, nickname: str) -> AuthSession:
        self.register_calls.append(phone)
        self.register_nicknames.append(nickname)
        return AuthSession(
            "Bearer access-token-for-" + str(self._ids[phone]),
            self._ids[phone],
            ROLE_USER,
        )

    def login(self, phone: str, code: str, device_id: str) -> AuthSession:
        self.login_calls.append(phone)
        user_id = self._ids[phone]
        role = self._roles[user_id]
        if user_id == 202 and self.wrong_reviewer_role:
            role = ROLE_USER
        return AuthSession(
            "Bearer login-token-for-" + str(user_id),
            user_id,
            role,
        )


class FakeMysql:
    def __init__(self, api: FakeApi | None = None) -> None:
        self.baseline_calls = 0
        self.role_calls: list[tuple[int, int, int]] = []
        self.reset_calls: list[tuple[int, int]] = []
        self.api = api

    def baseline_order_id(self) -> int:
        self.baseline_calls += 1
        return 17

    def assign_roles(self, customer_id: int, reviewer_id: int, executor_id: int) -> None:
        self.role_calls.append((customer_id, reviewer_id, executor_id))
        if self.api is not None:
            self.api._roles[reviewer_id] = ROLE_FINANCE_APPROVER
            self.api._roles[executor_id] = ROLE_FINANCE_EXECUTOR

    def reset_roles(self, reviewer_id: int, executor_id: int) -> None:
        self.reset_calls.append((reviewer_id, executor_id))
        if self.api is not None:
            self.api._roles[reviewer_id] = ROLE_USER
            self.api._roles[executor_id] = ROLE_USER


def _private_root() -> tempfile.TemporaryDirectory[str]:
    return tempfile.TemporaryDirectory(prefix="m5-finance-fixture-")


def _config(root: str) -> FinanceFixtureConfig:
    state_parent = Path(root) / "private-state"
    state_parent.mkdir(mode=0o700)
    os.chmod(state_parent, 0o700)
    return FinanceFixtureConfig(
        base_url="http://127.0.0.1:18080",
        fixture_id="m5-fresh-offline-finance",
        run_id="m5-finance-offline-test",
        backend_sha="a" * 40,
        customer_phone="13900000001",
        reviewer_phone="13900000002",
        executor_phone="13900000003",
        public_client_id="mobile-public-offline",
        mysql_container="voice-social-m3-development-mysql-1",
        state_file=str(state_parent / "fixture.json"),
    )


class FinanceFixtureContractTest(unittest.TestCase):
    def test_fixture_id_is_required_and_derives_customer_nickname(self) -> None:
        fixture_id = "m5-fresh-fixture.with:scope"
        expected = "m5-" + hashlib.sha256(fixture_id.encode("utf-8")).hexdigest()[:13]
        self.assertTrue(FIXTURE_ID_RE.fullmatch(fixture_id))
        self.assertEqual(_fixture_nickname(fixture_id), expected)
        for invalid in ("", "m5-old-fixture", "m5-fresh-", "m5-fresh- " + "x"):
            with self.subTest(invalid=invalid):
                self.assertIsNone(FIXTURE_ID_RE.fullmatch(invalid))

    def test_self_test_is_provider_free_and_subprocess_free(self) -> None:
        with patch("m5_alipay_dev_finance_fixture.subprocess.run") as run:
            self.assertEqual(_self_test(), 0)
            run.assert_not_called()

    def test_default_run_is_blocked_without_protected_environment(self) -> None:
        output = io.StringIO()
        error = io.StringIO()
        with patch.dict(os.environ, {}, clear=True), redirect_stdout(output), redirect_stderr(error):
            exit_code = main(["--run"])
        self.assertEqual(exit_code, 2)
        payload = json.loads(output.getvalue())
        self.assertEqual(payload["status"], "FAIL")
        self.assertEqual(payload["category"], "CONFIGURATION")
        self.assertFalse(payload["providerInvocation"])
        self.assertNotIn("phone", output.getvalue().lower())
        self.assertEqual(error.getvalue(), "")

    def test_argument_errors_do_not_echo_an_accidental_protected_value(self) -> None:
        output = io.StringIO()
        error = io.StringIO()
        accidental_value = "Bearer accidental-token-value"
        with redirect_stdout(output), redirect_stderr(error):
            exit_code = main(["--run", "--unexpected", accidental_value])
        self.assertEqual(exit_code, 2)
        self.assertNotIn(accidental_value, output.getvalue())
        self.assertNotIn(accidental_value, error.getvalue())

    def test_config_requires_loopback_development_and_disabled_sms(self) -> None:
        with self.assertRaisesRegex(FinanceFixtureError, "CONFIGURATION"):
            validate_base_url("https://backend.example.test")
        with self.assertRaisesRegex(FinanceFixtureError, "CONFIGURATION"):
            validate_base_url("http://10.0.2.2:18080")
        with self.assertRaisesRegex(FinanceFixtureError, "CONFIGURATION"):
            validate_phone_triplet("13900000001", "13900000001", "13900000003")
        with self.assertRaisesRegex(FinanceFixtureError, "CONFIGURATION"):
            validate_development_mysql_container("voice-social-production-mysql-1")
        with self.assertRaisesRegex(FinanceFixtureError, "CONFIGURATION"):
            validate_development_mysql_container("voice-social-development-backend-1")
        with _private_root() as root:
            config = _config(root)
            environment = {
                "QA_M5_FINANCE_BACKEND_URL": config.base_url,
                "QA_M5_FINANCE_RUN_ID": config.run_id,
                "QA_M5_FINANCE_FIXTURE_ID": config.fixture_id,
                "QA_M5_FINANCE_BACKEND_SHA": config.backend_sha,
                "QA_M5_FINANCE_PROFILE": "production",
                "QA_M5_FINANCE_SMS_VENDOR_ENABLED": "false",
                "QA_M5_FINANCE_CUSTOMER_PHONE": config.customer_phone,
                "QA_M5_FINANCE_REVIEWER_PHONE": config.reviewer_phone,
                "QA_M5_FINANCE_EXECUTOR_PHONE": config.executor_phone,
                "QA_M5_FINANCE_PUBLIC_CLIENT_ID": config.public_client_id,
                "QA_M5_FINANCE_MYSQL_CONTAINER": config.mysql_container,
                "QA_M5_FINANCE_STATE_FILE": config.state_file,
            }
            with self.assertRaisesRegex(FinanceFixtureError, "CONFIGURATION"):
                read_config(environment)
            environment["QA_M5_FINANCE_PROFILE"] = "development"
            environment["QA_M5_FINANCE_SMS_VENDOR_ENABLED"] = "true"
            with self.assertRaisesRegex(FinanceFixtureError, "CONFIGURATION"):
                read_config(environment)

    def test_config_rejects_state_file_permissions_existing_file_and_symlink(self) -> None:
        with _private_root() as root:
            root_path = Path(root)
            broad = root_path / "broad"
            broad.mkdir(mode=0o755)
            os.chmod(broad, 0o755)
            with self.assertRaisesRegex(FinanceFixtureError, "CONFIGURATION"):
                prepare_state_target(str(broad / "state.json"))

            private = root_path / "private"
            private.mkdir(mode=0o700)
            os.chmod(private, 0o700)
            existing = private / "existing.json"
            existing.write_text("{}", encoding="utf-8")
            with self.assertRaisesRegex(FinanceFixtureError, "CONFIGURATION"):
                prepare_state_target(str(existing))

            link = private / "link.json"
            link.symlink_to(existing)
            with self.assertRaisesRegex(FinanceFixtureError, "CONFIGURATION"):
                prepare_state_target(str(link))

    def test_run_registers_three_users_assigns_two_roles_and_relogs_in(self) -> None:
        with _private_root() as root:
            config = _config(root)
            api = FakeApi()
            mysql = FakeMysql(api)
            waits: list[float] = []
            result = run_flow(
                config,
                api=api,
                mysql=mysql,
                sleeper=waits.append,
            )  # type: ignore[arg-type]
            self.assertEqual(result["status"], "PASS")
            self.assertEqual(waits, [SMS_REAUTHENTICATION_WAIT_SECONDS])
            self.assertEqual(result["roleAssignments"], 2)
            self.assertEqual(mysql.baseline_calls, 1)
            self.assertEqual(mysql.role_calls, [(101, 202, 303)])
            self.assertEqual(api.register_calls, [config.customer_phone, config.reviewer_phone, config.executor_phone])
            self.assertEqual(
                api.register_nicknames,
                [
                    "m5-" + hashlib.sha256(config.fixture_id.encode("utf-8")).hexdigest()[:13],
                    "M5 Finance Reviewer",
                    "M5 Finance Executor",
                ],
            )
            self.assertEqual(api.login_calls, [config.customer_phone, config.reviewer_phone, config.executor_phone])
            self.assertEqual(len(api.send_calls), 6)
            state_path = Path(config.state_file)
            self.assertTrue(state_path.is_file())
            self.assertFalse(state_path.is_symlink())
            self.assertEqual(stat.S_IMODE(state_path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(state_path.parent.stat().st_mode), 0o700)
            state = json.loads(state_path.read_text(encoding="utf-8"))
            self.assertEqual(set(state), STATE_KEYS)
            self.assertEqual(state["schemaVersion"], SCHEMA_VERSION)
            self.assertEqual(state["fixtureId"], config.fixture_id)
            self.assertEqual(state["customerUserId"], 101)
            self.assertEqual(state["reviewerUserId"], 202)
            self.assertEqual(state["executorUserId"], 303)
            self.assertEqual(state["orderBaselineId"], 17)
            self.assertNotIn("challenge", json.dumps(state).lower())

    def test_role_and_identity_invariants_are_fail_closed(self) -> None:
        with _private_root() as root:
            config = _config(root)
            customer = AuthSession("Bearer customer-token-0001", 1, ROLE_USER)
            reviewer = AuthSession("Bearer reviewer-token-0001", 1, ROLE_FINANCE_APPROVER)
            executor = AuthSession("Bearer executor-token-0001", 3, ROLE_FINANCE_EXECUTOR)
            with self.assertRaisesRegex(FinanceFixtureError, "INVARIANT_VIOLATION"):
                build_state(config, customer, reviewer, executor, 0)
            with self.assertRaisesRegex(FinanceFixtureError, "INVARIANT_VIOLATION"):
                build_state(
                    config,
                    AuthSession("Bearer duplicate-token-0001", 1, ROLE_USER),
                    AuthSession(
                        "Bearer duplicate-token-0001", 2, ROLE_FINANCE_APPROVER
                    ),
                    executor,
                    0,
                )

    def test_post_assignment_failure_resets_finance_roles(self) -> None:
        with _private_root() as root:
            config = _config(root)
            api = FakeApi()
            api.wrong_reviewer_role = True
            mysql = FakeMysql(api)
            with self.assertRaisesRegex(
                FinanceFixtureError, "INVARIANT_VIOLATION"
            ):
                run_flow(
                    config,
                    api=api,
                    mysql=mysql,
                    sleeper=lambda _seconds: None,
                )  # type: ignore[arg-type]
            self.assertEqual(mysql.reset_calls, [(202, 303)])
            self.assertEqual(api._roles[202], ROLE_USER)
            self.assertEqual(api._roles[303], ROLE_USER)

    def test_cooldown_wait_failure_never_assigns_finance_roles(self) -> None:
        with _private_root() as root:
            config = _config(root)
            api = FakeApi()
            mysql = FakeMysql(api)

            def interrupted(_seconds: float) -> None:
                raise FinanceFixtureError("API_UNAVAILABLE")

            with self.assertRaisesRegex(FinanceFixtureError, "API_UNAVAILABLE"):
                run_flow(
                    config,
                    api=api,
                    mysql=mysql,
                    sleeper=interrupted,
                )  # type: ignore[arg-type]
            self.assertEqual(mysql.role_calls, [])
            self.assertEqual(mysql.reset_calls, [])

    def test_state_write_never_overwrites_a_target(self) -> None:
        with _private_root() as root:
            config = _config(root)
            state = build_state(
                config,
                AuthSession("Bearer customer-token-0001", 101, ROLE_USER),
                AuthSession("Bearer reviewer-token-0001", 202, ROLE_FINANCE_APPROVER),
                AuthSession("Bearer executor-token-0001", 303, ROLE_FINANCE_EXECUTOR),
                0,
            )
            write_state(config.state_file, state)
            with self.assertRaisesRegex(FinanceFixtureError, "CONFIGURATION"):
                write_state(config.state_file, state)

    def test_sensitive_environment_values_do_not_appear_in_failure_output(self) -> None:
        output = io.StringIO()
        phone = "13900000001"
        token = "Bearer customer-token-secret-0001"
        environment = {
            "QA_M5_FINANCE_BACKEND_URL": "http://127.0.0.1:18080",
            "QA_M5_FINANCE_RUN_ID": "m5-finance-output-test",
            "QA_M5_FINANCE_BACKEND_SHA": "b" * 40,
            "QA_M5_FINANCE_PROFILE": "development",
            "QA_M5_FINANCE_SMS_VENDOR_ENABLED": "false",
            "QA_M5_FINANCE_CUSTOMER_PHONE": phone,
            "QA_M5_FINANCE_REVIEWER_PHONE": "13900000002",
            "QA_M5_FINANCE_EXECUTOR_PHONE": "13900000003",
            "QA_M5_FINANCE_PUBLIC_CLIENT_ID": "mobile-public-output",
            "QA_M5_FINANCE_MYSQL_CONTAINER": "voice-social-m3-development-mysql-1",
            # Missing state file intentionally stops before any request.
            "QA_M5_FINANCE_STATE_FILE": "",
        }
        with patch.dict(os.environ, environment, clear=True), redirect_stdout(output):
            self.assertEqual(main(["--run"]), 2)
        encoded = output.getvalue()
        self.assertNotIn(phone, encoded)
        self.assertNotIn(token, encoded)
        self.assertNotIn("customerBearer", encoded)

    def test_mysql_password_is_only_referenced_inside_container_shell(self) -> None:
        completed = type("Completed", (), {"returncode": 0, "stdout": b"17\n"})()
        with patch(
            "m5_alipay_dev_finance_fixture._docker_environment",
            return_value={"PATH": "/usr/bin:/bin", "DOCKER_HOST": "unix:///private/tmp/test.sock"},
        ), patch("m5_alipay_dev_finance_fixture.subprocess.run", return_value=completed) as run:
            self.assertEqual(
                MysqlExecutor("voice-social-m3-development-mysql-1").baseline_order_id(),
                17,
            )
        args = run.call_args.args[0]
        self.assertNotIn("database-password-value", " ".join(args))
        self.assertIn("MYSQL_ROOT_PASSWORD", args[-1])
        self.assertNotIn("MYSQL_ROOT_PASSWORD=", args[-1])
        self.assertNotIn('-p"$MYSQL_ROOT_PASSWORD"', args[-1])
        self.assertIn('MYSQL_PWD="$MYSQL_ROOT_PASSWORD"', args[-1])
        self.assertIs(run.call_args.kwargs["stderr"], __import__("subprocess").DEVNULL)

    def test_docker_routing_rejects_context_and_non_unix_hosts(self) -> None:
        with patch.dict(os.environ, {"DOCKER_CONTEXT": "remote"}, clear=True):
            with self.assertRaisesRegex(FinanceFixtureError, "CONFIGURATION"):
                _docker_environment()
        with patch.dict(os.environ, {"DOCKER_HOST": "tcp://example.test:2376"}, clear=True):
            with self.assertRaisesRegex(FinanceFixtureError, "CONFIGURATION"):
                _docker_environment()
        with tempfile.TemporaryDirectory(prefix="m5-docker-socket-") as root:
            socket_path = str(Path(root) / "docker.sock")
            server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                server.bind(socket_path)
                with patch.dict(
                    os.environ,
                    {"DOCKER_HOST": "unix://" + socket_path},
                    clear=True,
                ):
                    self.assertEqual(
                        _docker_environment()["DOCKER_HOST"],
                        "unix://" + socket_path,
                    )
            finally:
                server.close()


if __name__ == "__main__":
    unittest.main()
