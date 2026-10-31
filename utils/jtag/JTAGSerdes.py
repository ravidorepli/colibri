# SPDX-FileCopyrightText: 2026 CERN
#
# SPDX-License-Identifier: CERN-OHL-W-2.0

# JTAGSerdes.py
from __future__ import annotations

from typing import Union

from OCDInterface import OCDInterface


class JTAGSerdes(OCDInterface):
    """
    Thin wrapper around an OpenOCD TCL server to perform JTAG IR/DR scans
    for a SERDES-like transport.

    Assumptions:
      - `OCDInterface` provides connect() and send_command(cmd: str) -> str
      - The target server understands OpenOCD commands `irscan` and `drscan`.
      - Data is moved via DR scans using a hex payload.
    """

    def __init__(self, tap_name: str, host: str = "localhost", port: int = 4444):
        """
        Initialize the JTAGSerdes.

        Args:
            tap_name: Name of the JTAG TAP configured in OpenOCD.
            host: Host where OpenOCD is running.
            port: Port where OpenOCD's TCL server is listening.
        """
        self.tap_name: str = tap_name
        self.setup_done: bool = False
        self.userIR: str | None = None
        super().__init__(host, port)

    def setup(self, userIR: Union[int, str]) -> None:
        """
        Select the USERx instruction register (IR) prior to DR transactions.

        Args:
            userIR: USERx IR code. Accepts:
                - int (e.g., 0x23 or 35)
                - str in hex format (e.g., '0x23' or '23')
        """
        ir_str = self._normalize_hex(userIR)
        self.userIR = ir_str
        self.connect()
        # Set the IR for subsequent DR scans
        self.send_command(f"irscan {self.tap_name} {ir_str}")
        self.setup_done = True

    def exchange(self, data: bytes | bytearray) -> bytes:
        """
        Perform a DR scan with the provided data and return the response.

        Args:
            data: Bytes to shift into DR. Length determines bit count (8 * n).

        Returns:
            Raw response bytes from the DR scan.

        Raises:
            RuntimeError: if setup() has not been called.
            ValueError: if data is empty.
        """
        if not self.setup_done:
            raise RuntimeError("JTAGSerdes.setup() must be called before exchange().")
        if not data:
            raise ValueError("exchange() requires non-empty data.")

        bit_len = 8 * len(data)
        # OpenOCD drscan expects hex with optional 0x prefix; we include 0x for clarity.
        data_hex = "0x" + bytes(data).hex()

        # send_command returns a hex string response. Accepts with/without 0x prefix.
        res_hex = self.send_command(f"drscan {self.tap_name} {bit_len} {data_hex}")

        # Normalize and parse the hex response robustly
        res_hex = res_hex.strip().lower()
        if res_hex.startswith("0x"):
            res_hex = res_hex[2:]
        if len(res_hex) % 2 != 0:
            # If OpenOCD returned an odd-length hex, pad left (defensive)
            res_hex = "0" + res_hex

        return bytes.fromhex(res_hex)

    # ---- Helpers ----

    @staticmethod
    def _normalize_hex(value: Union[int, str]) -> str:
        """
        Normalize an int or hex-like string into '0x...' lowercase format.

        Examples:
            35 -> '0x23'
            '0x23' -> '0x23'
            '23' -> '0x23'
        """
        if isinstance(value, int):
            if value < 0:
                raise ValueError("IR value must be non-negative.")
            return f"0x{value:x}"
        s = value.strip().lower()
        if s.startswith("0x"):
            # Ensure no non-hex characters
            int(s, 16)
            return s
        # Plain hex without prefix
        int(s, 16)  # validate
        return "0x" + s


def test() -> None:
    """
    Minimal self-test that issues a DR scan after setting the IR.
    """
    jtg = JTAGSerdes("xcs7.tap")
    jtg.setup("0x23")
    tx = bytes.fromhex("010a0b0c0d")
    rx = jtg.exchange(tx)
    print(rx)         # raw bytes
    print(rx.hex())   # hex view


if __name__ == "__main__":
    test()