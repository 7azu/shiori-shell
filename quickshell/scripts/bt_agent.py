#!/usr/bin/env python3
# BlueZ pairing agent for services/BluetoothState.qml.
# Without an agent BlueZ can only pair with "Just Works"; keyboards, phones etc. want
# a code confirmed or typed in. This agent passes such requests on to Quickshell as
# JSON lines and waits for the answer on stdin.
#
# stdout (one line each):
#   {"type": "ready"}
#   {"type": "confirm",   "id": 3, "device": "/org/bluez/hci0/dev_..", "passkey": "123456"}
#   {"type": "authorize", "id": 4, "device": ".."}                       (pairing without a code)
#   {"type": "service",   "id": 5, "device": "..", "uuid": ".."}         (service of an unpaired device)
#   {"type": "pin",       "id": 6, "device": ".."}                       (enter a code, old style)
#   {"type": "passkey",   "id": 7, "device": ".."}                       (enter a number)
#   {"type": "display",   "device": "..", "passkey": "123456", "entered": 2}  (type it on the device)
#   {"type": "cancel"}                                                   (BlueZ cancelled)
#   {"type": "error", "error": ".."}
# stdin (one line each):
#   ok <id> [value]     or   no <id>

import json
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

AGENT_PATH = "/org/quickshell/btagent"
CAPABILITY = "KeyboardDisplay"


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


class Rejected(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Rejected"


class Agent(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, AGENT_PATH)
        self.bus = bus
        self.next_id = 1
        # id -> (ok_callback, err_callback, Art)
        self.pending = {}

    def _ask(self, kind, ok, err, **extra):
        rid = self.next_id
        self.next_id += 1
        self.pending[rid] = (ok, err, kind)
        emit(dict(type=kind, id=rid, **extra))

    def answer(self, line):
        parts = line.strip().split(" ", 2)
        if len(parts) < 2 or not parts[1].isdigit():
            return
        entry = self.pending.pop(int(parts[1]), None)
        if entry is None:
            return
        ok, err, kind = entry
        if parts[0] != "ok":
            err(Rejected("Abgelehnt"))
            return
        value = parts[2] if len(parts) > 2 else ""
        try:
            if kind == "pin":
                ok(dbus.String(value or "0000"))
            elif kind == "passkey":
                ok(dbus.UInt32(int(value or "0")))
            else:
                ok()
        except ValueError:
            err(Rejected("Invalid code"))

    def _paired(self, device):
        try:
            props = dbus.Interface(self.bus.get_object("org.bluez", device), "org.freedesktop.DBus.Properties")
            return bool(props.Get("org.bluez.Device1", "Paired"))
        except dbus.DBusException:
            return False

    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Release(self):
        pass

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="", async_callbacks=("ok", "err"))
    def AuthorizeService(self, device, uuid, ok, err):
        # Devices that are already paired may use their services without asking
        if self._paired(device):
            ok()
            return
        self._ask("service", ok, err, device=str(device), uuid=str(uuid))

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="s", async_callbacks=("ok", "err"))
    def RequestPinCode(self, device, ok, err):
        self._ask("pin", ok, err, device=str(device))

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="u", async_callbacks=("ok", "err"))
    def RequestPasskey(self, device, ok, err):
        self._ask("passkey", ok, err, device=str(device))

    @dbus.service.method("org.bluez.Agent1", in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        emit(dict(type="display", device=str(device), passkey="%06d" % passkey, entered=int(entered)))

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        emit(dict(type="display", device=str(device), passkey=str(pincode), entered=0))

    @dbus.service.method("org.bluez.Agent1", in_signature="ou", out_signature="", async_callbacks=("ok", "err"))
    def RequestConfirmation(self, device, passkey, ok, err):
        self._ask("confirm", ok, err, device=str(device), passkey="%06d" % passkey)

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="", async_callbacks=("ok", "err"))
    def RequestAuthorization(self, device, ok, err):
        self._ask("authorize", ok, err, device=str(device))

    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Cancel(self):
        self.pending.clear()
        emit(dict(type="cancel"))


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    agent = Agent(bus)
    loop = GLib.MainLoop()

    def register():
        try:
            mgr = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"), "org.bluez.AgentManager1")
            mgr.RegisterAgent(AGENT_PATH, CAPABILITY)
            mgr.RequestDefaultAgent(AGENT_PATH)
            emit(dict(type="ready"))
        except dbus.DBusException as e:
            emit(dict(type="error", error=e.get_dbus_message() or str(e)))
            return False
        return True

    # bluetoothd restarted -> the agent is gone, register again
    bus.watch_name_owner("org.bluez", lambda owner: owner and register())

    def on_stdin(_fd, cond):
        if cond & (GLib.IO_HUP | GLib.IO_ERR):
            loop.quit()
            return False
        line = sys.stdin.readline()
        if not line:
            loop.quit()
            return False
        agent.answer(line)
        return True

    GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_stdin)
    try:
        loop.run()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
