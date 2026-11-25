#!/bin/bash
# Launcher for the Pywalfox extension (native messaging, started by Zen).
# The bundled main.sh calls "python -m pywalfox" with the system Python - that does not know
# the module, because Pywalfox lives in its own environment via pipx. So here directly
# its Python. Registered in ~/.mozilla/native-messaging-hosts/pywalfox.json ("path").
# Note: "pywalfox install" rewrites the registration and points it at main.sh again.
exec "$HOME/.local/share/pipx/venvs/pywalfox/bin/python" -m pywalfox start
