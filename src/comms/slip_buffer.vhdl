--! @title Slip buffer
--! @file slip_buffer.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 25-06-2024
--! @version 0.1
--!
--! slip buffer for stream synchronization
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;

entity slip_buffer is
  generic (
    g_DATA_WIDTH : positive := 64
  );
  port (
    clk_i       : in    std_logic;
    reset_i     : in    std_logic;                                   --! active high
    --! slip pulse which triggers shift
    slip_i      : in    std_logic;
    --! @virtualbus Avalon-ST @dir in sink
    snk_data_i  : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0); --! data input
    snk_valid_i : in    std_logic;                                   --! input valid signal
    snk_ready_o : out   std_logic;                                   --! ready back pressure propagation
    --! @end
    --! @virtualbus Avalon-ST @dir out source
    src_valid_o : out   std_logic;                                   --! valid output signal
    src_ready_i : in    std_logic;                                   --! source ready signal
    src_data_o  : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0)  --! data output
  --! @end
  );
end entity slip_buffer;

architecture rtl of slip_buffer is

  constant c_BUF_WIDTH : positive := g_DATA_WIDTH * 2;

  type sig_t is record
    valid : std_logic;
    ready : std_logic;
    buf   : std_logic_vector(g_DATA_WIDTH * 2 - 1 downto 0);
    data  : src_data_o'subtype;
    slip  : natural range 0 to g_DATA_WIDTH - 1;
  end record sig_t;

  signal rreg : sig_t;
  signal rcmb : sig_t;

begin

  proc_slip_main : process (all) is

    variable v_int : sig_t;

  begin

    v_int := rreg;
    -- consume buffer
    if (src_ready_i = '1' and rreg.valid = '1') then
      v_int.valid := '0';
    end if;

    -- drive backpressure based on buffer status
    v_int.ready := not v_int.valid;
    -- if input is available
    if (snk_valid_i = '1' and v_int.valid = '0') then
      v_int.valid := '1';
      v_int.buf   := v_int.buf(g_DATA_WIDTH - 1 downto 0) & snk_data_i;
    end if;

    -- slip offset counter
    if (slip_i) then
      if (rreg.slip = g_DATA_WIDTH - 1) then
        v_int.slip := 0;
      else
        v_int.slip := v_int.slip + 1;
      end if;
    end if;

    -- output mux logic
    for i in 0 to g_DATA_WIDTH - 1 loop

      if (i = v_int.slip) then
        v_int.data := v_int.buf(g_DATA_WIDTH - 1 + i downto i);
      end if;

    end loop;

    if (reset_i) then
      v_int.valid := '0';
      v_int.ready := '0';
      v_int.slip  := 0;
      v_int.buf   := (others => '0');
      v_int.data  := (others => '0');
    end if;

    rcmb <= v_int;

  end process proc_slip_main;

  rreg <= rcmb when rising_edge(clk_i);

  src_valid_o <= rreg.valid;
  snk_ready_o <= rcmb.ready;
  src_data_o  <= rreg.data;

end architecture rtl;
