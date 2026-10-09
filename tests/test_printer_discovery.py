"""
Tests for finding the printer IP address on the local network.

Run from the repository root with:

    python -m unittest discover tests
"""
import errno
import os
import sys
import tempfile
import unittest

from datetime import datetime
from unittest import mock

# Keep the tests away from the real configuration directory.
_config_dir = tempfile.TemporaryDirectory()
os.environ["ANKERCTL_CONFIG_DIR"] = _config_dir.name

import flask

import cli.config
import cli.model
import cli.pppp
import web
import web.config
import web.service.pppp

from libflagship.ppppapi import AnkerPPPPBaseApi

PRINTER_DUID = "EUPRAKM-001234-ABCDE"
PRINTER_IP = "192.0.2.10"


def broadcast_fails(err_no):
    """Makes sending the LAN search broadcast fail like macOS does without Local Network access."""
    return mock.patch.object(AnkerPPPPBaseApi, "send", side_effect=OSError(err_no, os.strerror(err_no)))


def printers_answer(*printers):
    return mock.patch.object(cli.pppp, "pppp_find_printer_ip_addresses", return_value=iter(printers))


class PrinterDiscoveryTest(unittest.TestCase):

    def setUp(self):
        self.config = cli.config.configmgr()
        self.assertEqual(str(self.config.config_root), _config_dir.name)
        self.config.save("default", cli.model.Config(
            account=cli.model.Account(auth_token="token", region="eu", user_id="user", email="user@example.com"),
            printers=[cli.model.Printer(
                id="1", sn="AK7ZRM0A00000000", name="Test Printer", model="V8111",
                create_time=datetime.now(), update_time=datetime.now(), wifi_mac="000000000000",
                ip_addr="", mqtt_key=b"\x00", api_hosts="", p2p_hosts="", p2p_duid=PRINTER_DUID, p2p_key="",
            )],
        ))

        web.app.config.update(config=self.config, printer_index=0, login=True, video_supported=False,
                              insecure=False, TESTING=True)
        web.config.printer_discovery = web.config.PrinterDiscovery()
        web.service.pppp.printer_discovery = web.config.printer_discovery

    def ip_addr(self):
        with self.config.open() as cfg:
            return cfg.printers[0].ip_addr

    def flashes(self, client):
        with client.session_transaction() as session:
            return session.get("_flashes", [])

    def test_updateip_broadcast_blocked_redirects_with_message(self):
        client = web.app.test_client()
        with broadcast_fails(errno.EHOSTUNREACH), mock.patch.object(sys, "platform", "darwin"):
            resp = client.post("/api/ankerctl/config/updateip")

        self.assertEqual(resp.status_code, 302)
        self.assertEqual(resp.headers["Location"], "/")
        [(category, message)] = self.flashes(client)
        self.assertEqual(category, "danger")
        self.assertIn("System Settings > Privacy & Security > Local Network", message)

    def test_updateip_other_os_error_redirects_with_message(self):
        client = web.app.test_client()
        with broadcast_fails(errno.ENETDOWN):
            resp = client.post("/api/ankerctl/config/updateip")

        self.assertEqual(resp.status_code, 302)
        [(category, message)] = self.flashes(client)
        self.assertEqual(category, "danger")
        self.assertIn("Could not search the local network for printers", message)

    def test_updateip_stores_found_address(self):
        client = web.app.test_client()
        with printers_answer((PRINTER_DUID, PRINTER_IP)):
            resp = client.post("/api/ankerctl/config/updateip")

        self.assertEqual(resp.status_code, 302)
        self.assertEqual(self.ip_addr(), PRINTER_IP)

    def test_pppp_worker_searches_for_missing_ip(self):
        svc = web.service.pppp.PPPPService()
        with printers_answer((PRINTER_DUID, PRINTER_IP)):
            printer = svc._search_ip_addr()

        self.assertEqual(printer.ip_addr, PRINTER_IP)
        self.assertEqual(self.ip_addr(), PRINTER_IP)

    def test_pppp_worker_search_is_rate_limited(self):
        svc = web.service.pppp.PPPPService()
        with printers_answer() as search:
            with self.assertLogs(level="WARNING") as logs:
                self.assertRaises(TimeoutError, svc._search_ip_addr)
            self.assertIn("did not answer the local network search", logs.output[0])

            # a second attempt right away does not search again
            self.assertRaises(TimeoutError, svc._search_ip_addr)
            self.assertEqual(search.call_count, 1)

    def test_pppp_worker_logs_hint_when_broadcast_blocked(self):
        svc = web.service.pppp.PPPPService()
        with broadcast_fails(errno.EHOSTUNREACH), mock.patch.object(sys, "platform", "darwin"):
            with self.assertLogs(level="WARNING") as logs:
                self.assertRaises(TimeoutError, svc._search_ip_addr)

        self.assertIn("Privacy & Security > Local Network", logs.output[0])
        self.assertNotIn("Traceback", "\n".join(logs.output))
        self.assertIn("Local Network", web.config.printer_discovery.last_error_hint)

    def test_login_searches_for_printers(self):
        with web.app.test_request_context(), printers_answer((PRINTER_DUID, PRINTER_IP)):
            web.search_printers_after_login(self.config)
            messages = [message for _, message in flask.get_flashed_messages(with_categories=True)]

        self.assertEqual(self.ip_addr(), PRINTER_IP)
        self.assertEqual(messages, ["Found printer(s) Test Printer on the local network"])

    def test_login_reports_blocked_broadcast(self):
        with web.app.test_request_context(), broadcast_fails(errno.EHOSTUNREACH), \
                mock.patch.object(sys, "platform", "darwin"):
            web.search_printers_after_login(self.config)
            flashes = flask.get_flashed_messages(with_categories=True)

        self.assertEqual([category for category, _ in flashes], ["warning"])
        self.assertIn("Local Network", flashes[0][1])


if __name__ == "__main__":
    unittest.main()
