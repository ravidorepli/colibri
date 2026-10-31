--==================================================================================================
--! @brief Avalon-ST Simple Clock Domain Crossing

--! @author Alberto Perro alberto.perro <at> cern.ch
--! @date 15-05-2025 Created
--! @version 0.1
--! @copyright CERN 2025
-- SPDX-FileCopyrightText: 2026 CERN
-- SPDX-License-Identifier: CERN-OHL-W-2.0
--==================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library colibri;
  use colibri.types.all;
  use colibri.utils.all;

----------------------------------------------------------------------------------------------------

entity avst_cdc is
  generic (
    g_DATA_WIDTH : positive := 16
  );
  port (
    --! reset
    reset_i     : in    std_logic;
    --! Clocks
    snk_clk_i   : in    std_logic;
    src_clk_i   : in    std_logic;
    --! Avalon stream input
    snk_ready_o : out   std_logic;
    snk_valid_i : in    std_logic;
    snk_sop_i   : in    std_logic;
    snk_eop_i   : in    std_logic;
    snk_empty_i : in    unsigned(log2ceil(g_DATA_WIDTH) - 1 downto 0);
    snk_data_i  : in    std_logic_vector(g_DATA_WIDTH - 1 downto 0);

    --! Avalon stream output
    src_ready_i : in    std_logic;
    src_valid_o : out   std_logic;
    src_sop_o   : out   std_logic;
    src_eop_o   : out   std_logic;
    src_empty_o : out   unsigned(log2ceil(g_DATA_WIDTH) - 1 downto 0);
    src_data_o  : out   std_logic_vector(g_DATA_WIDTH - 1 downto 0)
  );
end entity avst_cdc;

architecture rtl of avst_cdc is

  subtype avst_t is avst_master_t(
        data(g_DATA_WIDTH - 1 downto 0),
        empty(log2ceil(g_DATA_WIDTH) - 1 downto 0)
    );

  constant c_AVST_INIT : avst_t :=
  (
    data  => (others => '0'),
    empty => (others => '0'),
    sop   => '0',
    eop   => '0',
    valid => '0'
  );

  signal snk_avst_r : avst_t;
  signal snk_ready  : std_logic;
  signal src_avst_r : avst_t;
  signal src_ready  : std_logic;

  signal snk_feedback : std_logic;
  signal snk_return   : std_logic;
  signal src_feedback : std_logic;
  signal src_return   : std_logic;
  signal handshake    : std_logic;
  signal snk_reset    : std_logic;
  signal src_reset    : std_logic;

  -- CDC attributes for ALTERA/INTEL
  attribute preserve                       : boolean;
  attribute altera_attribute               : string;
  attribute preserve of snk_avst_r : signal is true;
  attribute preserve of src_avst_r : signal is true;
  -- CDC attributes for XILINX/AMD
  attribute dont_touch : boolean;
  attribute dont_touch of snk_avst_r : signal is TRUE;
  attribute dont_touch of src_avst_r : signal is TRUE;

begin

  snk_reset_inst : entity work.synchro_reset
    port map (
      clk_i   => snk_clk_i,
      reset_i => reset_i,
      reset_o => snk_reset
    );

  src_reset_inst : entity work.synchro_reset
    port map (
      clk_i   => src_clk_i,
      reset_i => reset_i,
      reset_o => src_reset
    );

  sync_feedback_snk_inst : entity colibri.synchro
    generic map (
      g_DATA_LENGTH => 1
    )
    port map (
      clk_i     => snk_clk_i,
      reset_i   => reset_i,
      data_i    => (others => src_feedback),
      data_o(0) => snk_feedback
    );

  sync_feedback_src_inst : entity colibri.synchro
    generic map (
      g_DATA_LENGTH => 1
    )
    port map (
      clk_i     => src_clk_i,
      reset_i   => reset_i,
      data_i    => (others => snk_return),
      data_o(0) => src_return
    );

  proc_snk_handle : process (snk_clk_i) is
  begin

    if rising_edge(snk_clk_i) then
      if (snk_reset) then
        snk_return <= '0';
        snk_avst_r <= c_AVST_INIT;
      end if;
      if (snk_ready_o = '1') then
        snk_avst_r.sop   <= snk_sop_i;
        snk_avst_r.eop   <= snk_eop_i;
        snk_avst_r.empty <= snk_empty_i;
        snk_avst_r.data  <= snk_data_i;
      end if;

      if (snk_valid_i = '1') then
        snk_return <= snk_feedback;
      end if;
    end if;

  end process proc_snk_handle;

  snk_ready_o <= snk_feedback xor snk_return;

  proc_src_handle : process (src_clk_i) is
  begin

    if rising_edge(src_clk_i) then
      if (src_reset = '1') then
        src_feedback <= '1';
        handshake    <= '0';
        src_avst_r   <= c_AVST_INIT;
        src_valid_o  <= '0';
      else
        if ((src_return xor handshake) and not src_valid_o) then
          src_valid_o  <= '1';
          src_avst_r   <= snk_avst_r;
          src_feedback <= not src_feedback;
        end if;

        if (src_ready_i and src_valid_o) then
          src_valid_o <= '0';
          handshake   <= not handshake;
        end if;
      end if;
    end if;

  end process proc_src_handle;

  src_sop_o   <= src_avst_r.sop;
  src_eop_o   <= src_avst_r.eop;
  src_empty_o <= src_avst_r.empty;
  src_data_o  <= src_avst_r.data;

end architecture rtl;
