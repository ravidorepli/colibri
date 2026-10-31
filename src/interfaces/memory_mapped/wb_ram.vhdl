--! @title Wishbone RAM interface
--! @file wb_ram.vhdl
--! @author Alberto Perro (alberto.perro at cern.ch)
--! @date 21-05-2024
--! @version 0.1

--! Release log:
--! - 0.1 first release
--!
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

library colibri;
  use colibri.utils.all;

entity wb_ram is
  generic (
    --! number of words to store in RAM
    g_N_WORDS       : positive;
    --! wishbone data width
    g_WB_DATA_WIDTH : positive := 32;
    --! wishbone address width
    g_WB_ADDR_WIDTH : positive := 32
  );
  port (
    clk_i    : in    std_logic;
    reset_i  : in    std_logic;
    --! @virtualbus wishbone @dir inout wishbone B4 memory mapped slave
    wb_adr_i : in    unsigned(g_WB_ADDR_WIDTH - 1 downto 0);
    wb_dat_i : in    std_logic_vector(g_WB_DATA_WIDTH - 1 downto 0);
    wb_dat_o : out   std_logic_vector(g_WB_DATA_WIDTH - 1 downto 0);
    wb_we_i  : in    std_logic;
    wb_sel_i : in    std_logic_vector(g_WB_DATA_WIDTH / 8 - 1 downto 0);
    wb_stb_i : in    std_logic;
    wb_cyc_i : in    std_logic;
    wb_ack_o : out   std_logic;
    wb_err_o : out   std_logic
  --! @end
  );
end entity wb_ram;

architecture rtl of wb_ram is

  signal word_addr  : unsigned(g_WB_ADDR_WIDTH - 1 downto 0);
  signal addr       : unsigned(log2ceil(g_N_WORDS) - 1 downto 0);     --! ram address to write to
  signal we         : std_logic;                                      --! write request
  signal data       : std_logic_vector(g_WB_DATA_WIDTH - 1 downto 0); --! data_i to write
  signal q          : std_logic_vector(g_WB_DATA_WIDTH - 1 downto 0); --! data_i to read
  signal valid_addr : std_logic;

begin

  word_addr  <= wb_adr_i / (g_WB_DATA_WIDTH / 8);
  valid_addr <= not (or word_addr(word_addr'left downto addr'length));
  we         <= wb_we_i and wb_stb_i and wb_cyc_i and valid_addr;
  addr       <= word_addr(addr'range) when valid_addr else
                (others => '0');
  wb_dat_o   <= q when wb_cyc_i and wb_ack_o else
                (others => '0');
  data       <= wb_dat_i when wb_stb_i and wb_cyc_i and valid_addr else
                (others => '0');

  proc_wb_iface : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (reset_i = '1') then
        wb_ack_o <= '0';
        wb_err_o <= '0';
      else
        wb_ack_o <= '0';
        wb_err_o <= '0';
        if (wb_stb_i and wb_cyc_i) then
          if (valid_addr) then
            wb_ack_o <= '1';
          else
            wb_err_o <= '1';
          end if;
        end if;
      end if;
    end if;

  end process proc_wb_iface;

  ram_inst : entity colibri.ram
    generic map (
      g_N_WORDS      => g_N_WORDS,
      g_DATA_WIDTH   => g_WB_DATA_WIDTH,
      g_REGISTER_IN  => false,
      g_REGISTER_OUT => true
    )
    port map (
      clk_i   => clk_i,
      reset_i => reset_i,
      addr_i  => addr,
      we_i    => we,
      data_i  => data,
      q_o     => q
    );

end architecture rtl;
