import json
import logging as log

from datetime import datetime, timedelta

from ..lib.service import Service, ServiceRestartSignal, ServiceStoppedError
from .. import app
from ..config import printer_discovery, search_error_message

import cli.pppp

from libflagship.pktdump import PacketWriter
from libflagship.pppp import P2PCmdType, PktClose, Duid, Type, Xzyh, Aabb
from libflagship.ppppapi import AnkerPPPPAsyncApi, PPPPState


# Minimum number of seconds between automatic searches for the printer IP address
IP_SEARCH_INTERVAL = 30


class PPPPService(Service):

    def api_command(self, commandType, **kwargs):
        if not hasattr(self, "_api"):
            raise ConnectionError("No pppp connection")
        cmd = {
            "commandType": commandType,
            **kwargs
        }
        return self._api.send_xzyh(
            json.dumps(cmd).encode(),
            cmd=P2PCmdType.P2P_JSON_CMD,
            block=False
        )

    def worker_start(self):
        print("PPPP worker_start BEGIN")
        config = app.config["config"]

        deadline = datetime.now() + timedelta(seconds=15)

        with config.open() as cfg:
            if not cfg:
                raise ServiceStoppedError("No config available")
            printer = cfg.printers[app.config["printer_index"]]

        if not printer.ip_addr:
            printer = self._search_ip_addr()

        try:
            import platform
            if platform.system() == "Windows":
                api = AnkerPPPPAsyncApi.open_broadcast("0.0.0.0")
                api.duid = Duid.from_string(printer.p2p_duid)
            else:
                api = AnkerPPPPAsyncApi.open_lan(Duid.from_string(printer.p2p_duid), host=printer.ip_addr)
        except Exception as e:
            print(f"CRASH IN WORKER START PLATFORM: {e}")
            import traceback; traceback.print_exc()
            raise
        
        if app.config["pppp_dump"]:
            dumpfile = app.config["pppp_dump"]
            log.info(f"Logging all pppp traffic to {dumpfile!r}")
            pktwr = PacketWriter.open(dumpfile)
            api.set_dumper(pktwr)

        log.debug(f"Trying connect to printer {printer.name} ({printer.p2p_duid}) over pppp using ip {printer.ip_addr}")

        try:
            print("PPPPService: Trying connect over pppp")
            api.connect_lan_search()

            while api.state != PPPPState.Connected:
                if datetime.now() > deadline:
                    print('PPPPService deadline exceeded')
                    raise TimeoutError("Connection timeout")
                try:
                    msg = api.poll(timeout=0.1)
                except TimeoutError:
                    print('PPPPService poll timeout', api.state)
                    pass
                except StopIteration:
                    print('PPPPService stop iteration')
                    raise ConnectionRefusedError("Connection rejected by device")
        except Exception as e:
            hint = cli.pppp.pppp_network_error_hint(e)
            if hint:
                raise ServiceStoppedError(f"Cannot connect to printer {printer.name}: {hint}") from None
            print(f"CRASH IN WORKER START CONNECT: {e}")
            import traceback; traceback.print_exc()
            raise

        log.info(f"Successfully connected to printer {printer.name} ({printer.p2p_duid}) over pppp using ip {printer.ip_addr}")
        log.info("Established pppp connection")
        self._api = api

    def _search_ip_addr(self):
        """
        Searches the local network for the printer when the configuration has
        no IP address for it (the Anker cloud does not always report one), and
        returns the updated printer.

        Searches run at most every IP_SEARCH_INTERVAL seconds. Start attempts
        in between raise TimeoutError, which the service retries without
        logging, so the log is not flooded every second.
        """
        config = app.config["config"]

        try:
            result = printer_discovery.search(config, min_interval=IP_SEARCH_INTERVAL)
        except OSError as err:
            log.warning(f"{self.name}: Printer IP address not available. {search_error_message(err)}")
            raise TimeoutError("Printer IP address not available") from None

        if result is None:
            raise TimeoutError("Printer IP address not available")

        with config.open() as cfg:
            printer = cfg.printers[app.config["printer_index"]]

        if not printer.ip_addr:
            log.warning(f"{self.name}: Printer {printer.name} did not answer the local network search. "
                        f"Make sure it is turned on and connected to the same network as ankerctl. "
                        f"Searching again in {IP_SEARCH_INTERVAL} seconds.")
            raise TimeoutError("Printer IP address not available")

        log.info(f"{self.name}: Found printer {printer.name} at {printer.ip_addr}")
        return printer

    def _recv_aabb(self, fd):
        data = fd.read(12)
        aabb = Aabb.parse(data)[0]
        p = data + fd.read(aabb.len + 2)
        aabb, data = Aabb.parse_with_crc(p)[:2]
        return aabb, data

    def worker_run(self, timeout):
        try:
            msg = self._api.poll(timeout=timeout)
        except ConnectionResetError:
            raise ServiceRestartSignal()

        if not msg:
            return

        if msg.type != Type.DRW:
            # forward messages other than Type.DRW without further processing
            self.notify((getattr(msg, "chan", None), msg))
            return

        ch = self._api.chans[msg.chan]

        with ch.lock:
            data = ch.peek(16, timeout=0)
            if not data:
                return

            if data[:4] == b'XZYH':
                hdr = ch.peek(16, timeout=0)
                if not hdr:
                    return

                xzyh = Xzyh.parse(hdr)[0]
                data = ch.read(xzyh.len + 16, timeout=0)
                if not data:
                    return None

                xzyh.data = data[16:]
                self.notify((msg.chan, xzyh))
            elif data[:2] == b'\xAA\xBB':
                aabb, data = self._recv_aabb(ch)
                if len(data) != 1:
                    raise ValueError(f"Unexpected reply from aabb request: {data}")

                aabb.data = data
                self.notify((msg.chan, aabb))
            else:
                raise ValueError(f"Unexpected data in stream: {data!r}")

    def worker_stop(self):
        self._api.send(PktClose())
        del self._api

    @property
    def connected(self):
        if not hasattr(self, "_api"):
            return False
        return self._api.state == PPPPState.Connected
