--! @title Self-synchronous scrambler
--! @file scrambler.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 07-07-2023
--! @version 0.1
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;
  use colibri.poly.all;

entity scrambler is
  generic (

    g_DATA_WIDTH     : positive         := 64;   --! word size
    --! polynomial used for scrambling x^58 + x^39 + 1
    --! Note: x^0 is ignored, MSB is to the RIGHT
    g_SCRAMBLER_POLY : std_logic_vector := c_SCR_10GBASE;
    --! initial value of the scrambler
    --! Note: MSB is to the RIGHT
    g_INIT_VAL       : std_logic_vector := gen_even(g_SCRAMBLER_POLY'length);
    g_INVERT_IN      : boolean          := true; --! invert bit order in input
    g_INVERT_OUT     : boolean          := true  --! invert bit order in output
  );
  port (
    clk_i       : in    std_logic;
    reset_i     : in    std_logic;                                   --! active high
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
end entity scrambler;

architecture rtl of scrambler is

  constant c_REGISTER_WIDTH : positive := g_SCRAMBLER_POLY'length + g_DATA_WIDTH;

  signal shift_reg  : std_logic_vector(c_REGISTER_WIDTH - 1 downto 0);
  signal tmpi_valid : std_logic;
  signal tmpo_valid : std_logic;
  signal tmpo_ready : std_logic;
  signal tmpi_ready : std_logic;
  signal tmpi_data  : std_logic_vector(snk_data_i'range);
  signal tmpr_data  : std_logic_vector(snk_data_i'range);
  signal o_data     : std_logic_vector(snk_data_i'range);
  signal reg_valid  : std_logic;
  signal cmb_valid  : std_logic;
  signal reg_data   : o_data'subtype;
  signal cmb_data   : o_data'subtype;

begin

  assert g_INIT_VAL'length = g_SCRAMBLER_POLY'length
    report "Init Value has to match Polynomial length"
    severity failure;

  -- input inversion
  gen_invert_in : if g_INVERT_IN generate
    tmpi_data <= invert_bit_order(snk_data_i);
  else
    generate
    tmpi_data <= snk_data_i;
  end generate gen_invert_in;

  -- output inversion
  gen_invert_out : if g_INVERT_OUT generate
    o_data <= invert_bit_order(tmpr_data);
  else
      generate
    o_data <= tmpr_data;
  end generate gen_invert_out;

  tmpi_valid  <= snk_valid_i;
  tmpr_data   <= shift_reg(shift_reg'length - 1 downto g_SCRAMBLER_POLY'length);
  snk_ready_o <= tmpi_ready;
  tmpi_ready  <= tmpo_ready;

  -- lfsr process
  proc_shift_register : process (clk_i) is

    variable v_reg    : std_logic_vector(c_REGISTER_WIDTH - 1 downto 0);
    variable v_xorbit : std_logic;

  begin

    if rising_edge(clk_i) then
      tmpo_valid <= '0';
      if (reset_i = '1') then
        shift_reg(shift_reg'length - 1 downto g_DATA_WIDTH) <= g_INIT_VAL;
      elsif (tmpi_valid = '1' and tmpi_ready = '1') then
        v_reg := shift_reg;

        for i in 0 to g_DATA_WIDTH - 1 loop
          v_xorbit := xorvec(v_reg(c_REGISTER_WIDTH - 1 downto g_DATA_WIDTH) and g_SCRAMBLER_POLY) xor tmpi_data(i);
          v_reg    := v_xorbit & v_reg(v_reg'length - 1 downto 1);
        end loop;

        shift_reg  <= v_reg;
        tmpo_valid <= '1';
      end if;
    end if;

  end process proc_shift_register;

  tmpo_ready <= src_ready_i or not cmb_valid;

  proc_reg_out : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        reg_valid <= '0';
      else
        if (src_ready_i = '0' and reg_valid = '0') then
          reg_valid <= tmpo_valid;
          reg_data  <= o_data;
        end if;
        if (src_ready_i = '1' and reg_valid = '1') then
          reg_valid <= '0';
        end if;
      end if;
    end if;

  end process proc_reg_out;

  src_data_o <= reg_data when reg_valid = '1' else
                o_data;
  cmb_valid  <= tmpo_valid or reg_valid;

  src_valid_o <= cmb_valid;

end architecture rtl;
