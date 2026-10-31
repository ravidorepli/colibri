--! @title Single Clock Gearbox
--! @file gearbox.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 12-06-2024
--! @version 0.3

--! @details
--! 0.3 reduced use of resources
--! 0.2 generalizing the data widths (unify `gearbox_up` and `_down`)
--! 0.1 initial release
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;

entity gearbox is
  generic (
    --! input data width
    g_INPUT_WIDTH  : integer;
    --! output data width
    g_OUTPUT_WIDTH : integer
  );
  port (
    clk_i       : in    std_logic;
    reset_i     : in    std_logic;
    --! @virtualbus stream @dir in sink
    snk_data_i  : in    std_logic_vector(g_INPUT_WIDTH - 1 downto 0);
    snk_valid_i : in    std_logic;
    snk_ready_o : out   std_logic;
    --! @end
    --! @virtualbus stream @dir out source
    src_data_o  : out   std_logic_vector(g_OUTPUT_WIDTH - 1 downto 0);
    src_valid_o : out   std_logic;
    src_ready_i : in    std_logic
  --! @end
  );
end entity gearbox;

architecture rtl of gearbox is

  -- Buffer size in bits (sufficiently big for optimal throughput)
  constant c_BUF_SIZE : integer := 2 * maximum(g_OUTPUT_WIDTH, g_INPUT_WIDTH)
    + minimum(g_OUTPUT_WIDTH, g_INPUT_WIDTH);

  signal buf   : std_logic_vector(c_BUF_SIZE - 1 downto 0);
  signal empty : std_logic;
  signal full  : std_logic;
  signal usedb : natural;

  signal cmb_valid : std_logic;
  signal reg_valid : std_logic;
  signal int_ready : std_logic;
  signal int_data  : std_logic_vector(src_data_o'range);

begin

  snk_ready_o <= not full and not reset_i;

  full  <= '1' when usedb > c_BUF_SIZE - g_INPUT_WIDTH else
           '0';
  empty <= '1' when usedb < g_OUTPUT_WIDTH else
           '0';

  -- pointer logic
  proc_ptr : process (clk_i) is

    variable v_used : natural;

  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        usedb <= 0;
      else
        v_used := usedb;
        if (snk_valid_i = '1' and full = '0') then
          v_used := v_used + g_INPUT_WIDTH;
        end if;

        if (empty = '0' and int_ready = '1') then
          v_used := v_used - g_OUTPUT_WIDTH;
        end if;
        usedb <= v_used;
      end if;
    end if;

  end process proc_ptr;

  -- writing data to buffer
  proc_wr_data : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '0' and snk_valid_i = '1' and full = '0') then
        buf <= buf(buf'left - g_INPUT_WIDTH downto 0) & snk_data_i;
      end if;
    end if;

  end process proc_wr_data;

  -- reading data from buffer
  proc_rd_data : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '0' and empty = '0' and int_ready = '1') then

        for i in g_OUTPUT_WIDTH to c_BUF_SIZE loop
          if (i = usedb) then
            int_data <= buf(i - 1 downto i - g_OUTPUT_WIDTH);
          end if;
        end loop;

      end if;
    end if;

  end process proc_rd_data;

  -- streaming buffer
  proc_buffer : process (all) is

    variable v_valid : std_logic;

  begin

    v_valid := reg_valid;

    if (src_ready_i = '1' and reg_valid = '1') then
      v_valid := '0';
    end if;

    if (empty = '0' and v_valid = '0') then
      int_ready <= '1';
      v_valid   := '1';
    else
      int_ready <= '0';
    end if;

    if (reset_i) then
      v_valid := '0';
    end if;

    cmb_valid <= v_valid;

  end process proc_buffer;

  reg_valid   <= cmb_valid when rising_edge(clk_i);
  src_valid_o <= reg_valid;
  src_data_o  <= int_data when reg_valid = '1' else
                 (others => '0');

end architecture rtl;
