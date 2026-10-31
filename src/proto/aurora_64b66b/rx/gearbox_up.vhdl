--! @brief Continuous Stream Upsizing Gearbox
--! @file gearbox_up.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 25-09-2024
--! @version 0.1
--! @copyright CERN 2026
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.utils.all;
--==================================================================================================
--! @brief Continuous Stream Upsizing Gearbox
--! @details
--! Generic upscaling gearbox for continuous streams on a single clock domain.
--! It includes a slip signal to shift the output (1 bit resolution).
--! Inspired by the work of Timon Heim for Yarr.
--! changelog:
--! - 0.1: initial release
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

entity gearbox_up is
  generic (
    --! input data width
    g_INPUT_WIDTH  : integer;
    --! output data width
    g_OUTPUT_WIDTH : integer
  );
  port (
    clk_i       : in    std_logic;
    reset_i     : in    std_logic;
    -- gearbox slip signal
    slip_i      : in    std_logic;
    --! @virtualbus stream @dir in sink
    snk_data_i  : in    std_logic_vector(g_INPUT_WIDTH - 1 downto 0);
    snk_valid_i : in    std_logic;
    --! @end
    --! @virtualbus stream @dir out source
    src_data_o  : out   std_logic_vector(g_OUTPUT_WIDTH - 1 downto 0);
    src_valid_o : out   std_logic
  --! @end
  );
end entity gearbox_up;

architecture rtl of gearbox_up is

  constant c_MIN : natural := minimum(snk_data_i'length, src_data_o'length);
  constant c_MAX : natural := maximum(snk_data_i'length, src_data_o'length);

  constant c_LCM       : natural := least_common_mult(snk_data_i'length, src_data_o'length);
  constant c_REMAINDER : natural := c_MAX rem c_MIN;
  constant c_MAX_COUNT : natural := c_LCM / c_MIN;
  constant c_MAX_SHIFT : natural := c_MAX / c_MIN;
  constant c_FLOOR     : natural := (c_MAX / c_MIN) * c_MIN;

  constant c_BUF_SIZE : natural := c_MAX + c_FLOOR;

  signal gearbox_cnt   : unsigned(log2ceil(c_MAX_COUNT - 1) downto 0);
  signal shift_cnt     : natural range 0 to c_BUF_SIZE / snk_data_i'length;
  signal buf           : std_logic_vector(c_BUF_SIZE - 1 downto 0);
  signal buf_watermark : std_logic;
  signal slip_cnt      : natural range 0 to c_REMAINDER;
  signal slip_seen     : std_logic;

begin

  proc_shift : process (clk_i, reset_i) is

    variable v_pos : natural range 0 to c_MAX_COUNT - 1;
    variable v_off : natural range 0 to c_BUF_SIZE;

  begin

    if (reset_i = '1') then
      buf           <= (others => '0');
      gearbox_cnt   <= (others => '0');
      src_valid_o   <= '0';
      src_data_o    <= (others => '0');
      shift_cnt     <= 0;
      slip_cnt      <= 0;
      buf_watermark <= '0';
      slip_seen     <= '0';
    elsif rising_edge(clk_i) then
      src_valid_o <= '0';
      -- if the input is valid
      if (snk_valid_i = '1') then
        shift_cnt <= shift_cnt + 1;
        buf       <= buf(buf'left - snk_data_i'length downto 0) & snk_data_i;
        v_pos     := to_integer(gearbox_cnt(log2ceil(c_MAX_COUNT - 1) - 1 downto 0));
        v_off     := c_BUF_SIZE - c_REMAINDER - (v_pos * c_REMAINDER - slip_cnt);
        -- if a slip signal is issued, remember it
        if (slip_i = '1') then
          slip_seen <= '1';
        end if;
        -- if there are enough words in the buffer
        if (shift_cnt = c_MAX_SHIFT - 1 and buf_watermark = '1') then
          shift_cnt   <= 0;
          src_valid_o <= '1';
          -- valid is zero if buffer is fully consumed
          if (gearbox_cnt = c_MAX_COUNT - 1) then
            gearbox_cnt <= (others => '0');
            src_valid_o <= '0';
          else
            gearbox_cnt <= gearbox_cnt + 1;
            src_data_o  <= buf(v_off - 1
                               downto v_off - src_data_o'length);
          end if;
          -- if slip has been seen
          if (slip_seen = '1') then
            slip_seen <= '0';
            if (slip_cnt = c_REMAINDER - 1) then
              slip_cnt    <= 0;
              gearbox_cnt <= gearbox_cnt;
            else
              -- if slip is less than normal shift
              slip_cnt <= slip_cnt + 1;
            end if;
          end if;
        else
          -- routine to fill buffer at the beginning
          if (shift_cnt = buf'length / snk_data_i'length - c_MAX_SHIFT and buf_watermark = '0') then
            buf_watermark <= '1';
            shift_cnt     <= 0;
          end if;
        end if;
      end if;
    end if;

  end process proc_shift;

end architecture rtl;
