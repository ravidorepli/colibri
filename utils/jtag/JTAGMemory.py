# SPDX-FileCopyrightText: 2026 CERN
#
# SPDX-License-Identifier: CERN-OHL-W-2.0

# jtag_memory.py
from __future__ import annotations

import struct
from time import sleep
from typing import Optional

from JTAGSerdes import JTAGSerdes


class JTAGMemory(JTAGSerdes):
    """
    High-level memory access wrapper over a JTAG SERDES transport.

    Protocol (as inferred from original code):
      - All exchanges are 5 bytes, with the first byte an opcode.
      - Opcodes:
          0x00: NOP/EMPTY   -> payload: 4 bytes of 0x00
          0x01: SET_ADDR    -> payload: 4-byte big-endian address
          0x02: READ        -> payload: 4 bytes of 0x00 (response carries data)
          0x03: WRITE       -> payload: 4 bytes of data to write
      - The device responds to each exchange; latest response is stored in
        `self.response`.

    Notes:
      - `exchange()` is inherited from JTAGSerdes and performs a
        full-duplex transaction, returning the device response as bytes.
      - Addresses are treated as 32-bit unsigned (big-endian on the wire).
      - Data words are exactly 4 bytes for read/write.
    """

    # Opcodes (documented for clarity)
    OPCODE_EMPTY = 0x00
    OPCODE_SET_ADDR = 0x01
    OPCODE_READ = 0x02
    OPCODE_WRITE = 0x03

    def __init__(self, tap_name: str, host: str = "localhost", port: int = 4444):
        """
        Initialize the JTAGMemory interface.

        Args:
            tap_name: TAP name/string for the underlying JTAGSerdes.
            host: Hostname of JTAG server/bridge.
            port: Port of JTAG server/bridge.
        """
        self.response: bytes = b""
        super().__init__(tap_name, host, port)

    def setup(self, user_ir: str) -> None:
        """
        Configure the TAP with a given USER IR and clear any pending state.

        Args:
            user_ir: The IR value (e.g., '0x23') expected by the target design.
        """
        super().setup(user_ir)
        self._empty()

    # --- Low-level operations (protocol helpers) ---

    def _setaddr(self, address: int) -> None:
        """
        Send a SET_ADDR command.

        Args:
            address: 32-bit unsigned address.
        """
        if not (0 <= address <= 0xFFFFFFFF):
            raise ValueError("address must be a 32-bit unsigned integer")
        payload = struct.pack(">I", address)
        tx = bytearray([self.OPCODE_SET_ADDR]) + payload
        self.response = self.exchange(tx)

    def _empty(self) -> None:
        """
        Send an EMPTY/NOP command (five bytes: opcode + 4 zeros).
        Useful to flush or clock the link for a clean state.
        """
        tx = bytearray([self.OPCODE_EMPTY, 0x00, 0x00, 0x00, 0x00])
        self.response = self.exchange(tx)

    def _wrdata(self, data: bytes | bytearray) -> None:
        """
        Send a WRITE command with 4 data bytes.

        Args:
            data: Exactly 4 bytes to write.
        """
        if len(data) != 4:
            raise ValueError("write data must be exactly 4 bytes")
        tx = bytearray([self.OPCODE_WRITE]) + bytearray(data)
        self.response = self.exchange(tx)

    def _rddata(self) -> None:
        """
        Send a READ command. The response will contain the read data.
        """
        tx = bytearray([self.OPCODE_READ, 0x00, 0x00, 0x00, 0x00])
        self.response = self.exchange(tx)

    # --- Public API ---

    def write(self, addr: int, data: bytes | bytearray) -> None:
        """
        Write a 32-bit word to a memory-mapped address.

        Args:
            addr: 32-bit address.
            data: 4-byte payload to write.
        """
        self._setaddr(addr)
        self._wrdata(data)
        # Important: actually call _empty() (bugfix from original code)
        self._empty()

    def read(self, addr: int) -> bytes:
        """
        Read a 32-bit word from a memory-mapped address.

        Args:
            addr: 32-bit address to read from.

        Returns:
            4-byte response as bytes.
        """
        self._setaddr(addr)
        self._rddata()
        self._empty()
        return self.response


def _demo_blink(jtg: JTAGMemory, addr: int, cycles: int = 4, period_s: float = 1.0) -> None:
    """
    Example: toggle a word at `addr` to 0x00000001 and 0x00000000.

    Args:
        jtg: An initialized JTAGMemory instance.
        addr: Target address to toggle.
        cycles: Number of on/off cycles.
        period_s: Delay between writes in seconds.
    """
    one = b"\x00\x00\x00\x01"
    zero = b"\x00\x00\x00\x00"
    for _ in range(cycles):
        jtg.write(addr, one)
        sleep(period_s)
        jtg.write(addr, zero)
        sleep(period_s)


def test() -> None:
    jtg = JTAGMemory("xcs7.tap")
    jtg.setup("0x23")

    # Example: toggle an LED mapped at this address (adjust as needed)
    _demo_blink(jtg, addr=0x0A0B0C0D, cycles=4, period_s=1.0)

    # Read back from address 0x0 and print as hex
    ret = jtg.read(0x00000000)
    print(ret.hex())


if __name__ == "__main__":
    test()