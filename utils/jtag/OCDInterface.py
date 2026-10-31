# SPDX-FileCopyrightText: 2026 CERN
#
# SPDX-License-Identifier: CERN-OHL-W-2.0

import socket
from typing import Optional


class OCDInterface:
    """
    Line-oriented client for OpenOCD's TCL/Telnet interface (default port 4444).
    Reads until the prompt and returns response WITHOUT the echoed command.
    """

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = 4444,
        timeout_sec: float = 5.0,
        prompt: bytes = b"> ",
        encoding: str = "utf-8",
    ):
        self.host = host
        self.port = port
        self.timeout_sec = timeout_sec
        self.prompt = prompt
        self.encoding = encoding
        self._sock: Optional[socket.socket] = None
        self._buffer = bytearray()

    # ---------- Lifecycle ----------

    def connect(self) -> None:
        if self._sock is not None:
            return
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(self.timeout_sec)
        try:
            s.connect((self.host, self.port))
            self._sock = s
            # Drain the initial banner/prompt
            self._drain_until_prompt()
        except Exception:
            s.close()
            self._sock = None
            raise

    def disconnect(self) -> None:
        if self._sock is not None:
            try:
                self._sock.shutdown(socket.SHUT_RDWR)
            except Exception:
                pass
            try:
                self._sock.close()
            finally:
                self._sock = None
        self._buffer.clear()

    def __enter__(self):
        self.connect()
        return self

    def __exit__(self, exc_type, exc, tb):
        self.disconnect()

    # ---------- Public API ----------

    def send_command(self, command: str, wait_for_prompt: bool = True) -> str:
        """
        Send a command and return response without the echoed command line.

        If wait_for_prompt is False, returns an empty string after sending.
        """
        if self._sock is None:
            raise RuntimeError("Not connected. Call connect() first.")

        clean_cmd = command.rstrip("\r\n")
        wire = (clean_cmd + "\n").encode(self.encoding)

        self._send_all(wire)

        if not wait_for_prompt:
            return ""

        raw_text = self._drain_until_prompt()

        # Strip echoed command (first line equals the command)
        lines = raw_text.splitlines()
        if lines and lines[0].strip() == clean_cmd:
            lines = lines[1:]
        
        return "".join(lines).strip().strip("\n").strip("\x00")

    # ---------- Helpers ----------

    def _send_all(self, data: bytes) -> None:
        assert self._sock is not None
        total = 0
        while total < len(data):
            sent = self._sock.send(data[total:])
            if sent == 0:
                raise ConnectionError("Socket connection broken during send.")
            total += sent

    def _recv_some(self) -> int:
        assert self._sock is not None
        chunk = self._sock.recv(4096)
        if not chunk:
            return 0
        self._buffer.extend(chunk)
        return len(chunk)

    def _drain_until_prompt(self) -> str:
        """
        Read until we detect a prompt line '> ' at the end.
        Return decoded text prior to the prompt.
        """
        assert self._sock is not None
        self._sock.settimeout(self.timeout_sec)

        def find_prompt_line(buf: bytearray) -> int:
            data = bytes(buf)
            # Look for a line that equals the prompt at the end
            # Find last newline to isolate the last line
            last_nl = max(data.rfind(b"\n"), data.rfind(b"\r"))
            if last_nl == -1:
                return -1
            tail = data[last_nl + 1 :]
            if tail == self.prompt or tail.startswith(self.prompt):
                return last_nl + 1
            return -1

        while True:
            # Check current buffer first (useful for initial connect)
            idx = find_prompt_line(self._buffer)
            if idx >= 0:
                data = bytes(self._buffer)
                # Response is everything before the prompt line; trim trailing EOLs
                response = data[:idx].rstrip(b"\r\n")
                self._buffer.clear()
                return response.decode(self.encoding, errors="replace")

            n = self._recv_some()
            if n == 0:
                # Connection closed; return what we have
                data = self._buffer.decode(self.encoding, errors="replace")
                self._buffer.clear()
                return data