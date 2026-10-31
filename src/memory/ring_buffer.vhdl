--! @file ring_buffer.vhdl
--! @brief Simple Ring Buffer
--! @author Alberto Perro
--! @date 23-01-2024 Created
--! @version 0.1
--! @copyright CERN 2024
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.utils.all;
  use colibri.types.all;

--==================================================================================================
--! @brief RAM-based simple ring buffer
--! @details
--! This entity implements a simple stream ring buffer.
--! Compared to a FIFO, it is possible to write when full, overwriting the oldest word in memory.

-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity ring_buffer is
  generic (

    --! size of buffer in words
    g_NUM_WORDS  : positive := 4;
    --! size of data words in bits
    g_DATA_WIDTH : positive := 8
  );
  port (
    clk_i       : in    std_logic;                                   --! common clock
    reset_i     : in    std_logic;                                   --! reset_i
    snk_data_i  : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0); --! data_i input
    snk_valid_i : in    std_logic;                                   --! valid input
    src_data_o  : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0); --! data output
    src_valid_o : out   std_logic;                                   --! valid output
    src_ready_i : in    std_logic                                    --! read request
  );
end entity ring_buffer;

architecture rtl of ring_buffer is

  signal mem : slv_array_t(0 to g_NUM_WORDS - 1)(g_DATA_WIDTH - 1 downto 0);

  type sig_t is record
    head  : integer range 0 to g_NUM_WORDS - 1;
    tail  : integer range 0 to g_NUM_WORDS - 1;
    usedw : integer range 0 to g_NUM_WORDS;
  end record sig_t;

  constant c_SIG_INIT : sig_t :=
  (
    head  => 0,
    tail  => 0,
    usedw => 0
  );

  signal rreg : sig_t;
  signal rcmb : sig_t;

begin

  rreg <= rcmb when rising_edge(clk_i);

  proc_main : process (all) is

    variable v_int : sig_t;

  begin

    v_int := rreg;

    -- tie data to memory

    -- advance write pointer
    if (snk_valid_i = '1') then
      if (rreg.head /= g_NUM_WORDS - 1) then
        v_int.head := rreg.head + 1;
      else
        v_int.head := 0;
      end if;
    end if;

    -- fill level count
    if (snk_valid_i) then
      if (src_ready_i = '0' or rreg.usedw = 0) then
        if (rreg.usedw /= g_NUM_WORDS) then
          v_int.usedw := rreg.usedw + 1;
        end if;
      end if;
    elsif (src_ready_i = '1' and rreg.usedw /= 0) then
      v_int.usedw := rreg.usedw - 1;
    end if;

    -- advance read pointer (write when full, read when not empty)
    if ((rreg.usedw = g_NUM_WORDS and snk_valid_i = '1') or (src_ready_i = '1' and rreg.usedw /= 0)) then
      if (rreg.tail /= g_NUM_WORDS - 1) then
        v_int.tail := rreg.tail + 1;
      else
        v_int.tail := 0;
      end if;
    end if;

    if (reset_i) then
      v_int := c_SIG_INIT;
    end if;

    rcmb <= v_int;

  end process proc_main;

  proc_mem : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (snk_valid_i) then
        mem(rreg.head) <= snk_data_i;
      end if;
    end if;

  end process proc_mem;

  src_data_o  <= mem(rreg.tail) when src_valid_o else
                 (others => '0');
  src_valid_o <= '1' when rreg.usedw /= 0 else
                 '0';

end architecture rtl;
