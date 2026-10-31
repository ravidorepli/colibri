# SPDX-FileCopyrightText: 2026 CERN
#
# SPDX-License-Identifier: CERN-OHL-W-2.0

import os
from vunit import VUnit
import itertools

GHDL_OPTS = ["-frelaxed", "-fsynopsys", "--syn-binding"]
NVC_A_OPTS = ["--relaxed"]
RIVIERA_OPTS = ["-relax"]
script_dir = os.path.dirname(__file__)
PROJ_ROOT = os.path.join(script_dir, "../../")

vu = VUnit.from_argv()
vu.add_vhdl_builtins()
vu.add_osvvm()
vu.add_com()

uvvm_util_lib = vu.add_library("uvvm_util")
uvvm_util_lib.add_source_files("UVVM/uvvm_util/src/*.vhd")

uvvm_vvc_framework_lib = vu.add_library("uvvm_vvc_framework")
uvvm_vvc_framework_lib.add_source_files("UVVM/uvvm_vvc_framework/src/*.vhd")

bitvis_vip_scoreboard_lib = vu.add_library("bitvis_vip_scoreboard")
bitvis_vip_scoreboard_lib.add_source_files("UVVM/bitvis_vip_scoreboard/src/*.vhd")

bitvis_vip_clock_generator_lib = vu.add_library("bitvis_vip_clock_generator")
bitvis_vip_clock_generator_lib.add_source_files(
    "UVVM/uvvm_vvc_framework/src_target_dependent/*.vhd"
)
bitvis_vip_clock_generator_lib.add_source_files(
    "UVVM/bitvis_vip_clock_generator/src/*.vhd"
)

bitvis_vip_avalon_st_lib = vu.add_library("bitvis_vip_avalon_st")
bitvis_vip_avalon_st_lib.add_source_files(
    "UVVM/uvvm_vvc_framework/src_target_dependent/*.vhd"
)
bitvis_vip_avalon_st_lib.add_source_files("UVVM/bitvis_vip_avalon_st/src/*.vhd")


bitvis_vip_axistream_lib = vu.add_library("bitvis_vip_axistream")
bitvis_vip_axistream_lib.add_source_files(
    "UVVM/uvvm_vvc_framework/src_target_dependent/*.vhd"
)
bitvis_vip_axistream_lib.add_source_files("UVVM/bitvis_vip_axistream/src/*.vhd")

colibri_lib = vu.add_library("colibri")
colibri_lib.add_source_files(
    os.path.join(PROJ_ROOT, "src/common/*.vhdl"), allow_empty=True
)
colibri_lib.add_source_files(
    os.path.join(PROJ_ROOT, "src/comms/*.vhdl"), allow_empty=True
)
colibri_lib.add_source_files(
    os.path.join(PROJ_ROOT, "src/memory/*.vhdl"), allow_empty=True
)
colibri_lib.add_source_files(
    os.path.join(PROJ_ROOT, "src/memory/*/*.vhdl"), allow_empty=True
)

tb_lib = vu.add_library("tb_lib")
tb_lib.add_source_files(os.path.join(PROJ_ROOT, "sim/memory/*.vhdl"), allow_empty=True)
tb_lib.add_source_files(os.path.join(PROJ_ROOT, "sim/memory/rom/*.vhdl"), allow_empty=True)
tb_lib.add_source_files(
    os.path.join(PROJ_ROOT, "sim/memory/packet_fifo/*.vhdl"), allow_empty=True
)
tb_lib.add_source_files(
    os.path.join(PROJ_ROOT, "sim/memory/packet_cc_fifo/*.vhdl"), allow_empty=True
)
tb_lib.add_source_files(
    os.path.join(PROJ_ROOT, "sim/memory/packet_cc_ram_fifo/*.vhdl"), allow_empty=True
)

vu.add_compile_option("ghdl.a_flags", GHDL_OPTS)
vu.add_compile_option("rivierapro.vcom_flags", RIVIERA_OPTS)
vu.add_compile_option("nvc.a_flags", NVC_A_OPTS)
for tb in tb_lib.get_test_benches():
    tb.set_sim_option("modelsim.vsim_flags.gui", ["-voptargs=+acc", "-debugdb"])
    tb.set_sim_option(
        "rivierapro.vsim_flags.gui",
        ["-voptargs=+acc", "-debugdb", "+access +r", "-advdataflow"],
    )
    tb.set_sim_option("ghdl.elab_flags", GHDL_OPTS)
    tb.set_sim_option("nvc.heap_size", "256m")
    tb.set_sim_option("nvc.sim_flags", ["--wave=wave.fst", "--dump-arrays"])
    tb.set_sim_option("disable_ieee_warnings", True)
    # tb.set_sim_option("ghdl.sim_flags", ["--assert-level=warning"])
    for test in tb.get_tests("ram_coverage"):
        for rin, rout, wr_first in itertools.product([True,False],[True,False],[True,False]):
            test.add_config(
                name="rin=%s,rout=%s,wr_first=%s" %(rin, rout, wr_first),
                generics=dict(g_REGISTER_IN=rin,g_REGISTER_OUT=rout,g_WRITE_FIRST=wr_first))

    # Simple Dual-Port RAM with write byte-enable ------------------------------
    if tb.name == "simple_dpram_be_tb":
        for g_BYTE_WIDTH in [8, 9]:
            for g_WORD_BYTES in [1, 5, 8]:
                tb.add_config(
                    name = f'byte={g_BYTE_WIDTH},width={g_WORD_BYTES}',
                    generics = {
                        "g_BYTE_WIDTH" : g_BYTE_WIDTH,
                        "g_WORD_BYTES" : g_WORD_BYTES
                        }
                        )
    # Simple Dual-Port RAM with mixed width support ------------------------------
    if tb.name == "simple_dpram_tb":
        for g_A_DATA_WIDTH, g_B_DATA_WIDTH, g_IMPL_STYLE in itertools.product([8, 16, 32],[8, 16, 32],[0,1]):
                tb.add_config(
                    name = f'a={g_A_DATA_WIDTH},b={g_B_DATA_WIDTH},i={g_IMPL_STYLE}',
                    generics = {
                        "g_A_DATA_WIDTH" : g_A_DATA_WIDTH,
                        "g_B_DATA_WIDTH" : g_B_DATA_WIDTH,
                        "g_IMPL_STYLE": g_IMPL_STYLE
                        }
                        )
    # True Dual-Port RAM with mixed width support ------------------------------
    if tb.name == "true_dpram_tb":
        for g_A_DATA_WIDTH, g_B_DATA_WIDTH, g_IMPL_STYLE in itertools.product([8, 16, 32],[8, 16, 32], [0,1]):
                tb.add_config(
                    name = f'a={g_A_DATA_WIDTH},b={g_B_DATA_WIDTH},i={g_IMPL_STYLE}',
                    generics = {
                        "g_A_DATA_WIDTH" : g_A_DATA_WIDTH,
                        "g_B_DATA_WIDTH" : g_B_DATA_WIDTH,
                        "g_IMPL_STYLE": g_IMPL_STYLE
                        }
                        )
    # Dual Clock RAM-based FIFO mixed width support ------------------------------
    if tb.name == "cc_ram_fifo_tb":
        for g_INPUT_WIDTH, g_OUTPUT_WIDTH in itertools.product([8, 16, 32],[8, 16, 32]):
                tb.add_config(
                    name = f'w={g_INPUT_WIDTH},r={g_OUTPUT_WIDTH}',
                    generics = {
                        "g_INPUT_WIDTH" : g_INPUT_WIDTH,
                        "g_OUTPUT_WIDTH" : g_OUTPUT_WIDTH
                        }
                        )
    # Dual Clock FIFO first word fall through support ------------------------------
    if tb.name == "cc_fifo_tb":
        for g_ENABLE_FWFT in [False, True]:
                tb.add_config(
                    name = f"fwft={g_ENABLE_FWFT}",
                    generics = {
                        "g_ENABLE_FWFT" : g_ENABLE_FWFT
                        }
                        )
    # Dual Clock Packet RAM-based FIFO ------------------------------
    if tb.name == "packet_cc_ram_fifo_tb":
        for g_SNK_DATA_WIDTH, g_SRC_DATA_WIDTH in itertools.product([16, 32],[16, 32]):
                tb.add_config(
                    name = f"snkw={g_SNK_DATA_WIDTH},srcw={g_SRC_DATA_WIDTH}",
                    generics = {
                        "g_SNK_DATA_WIDTH" : g_SNK_DATA_WIDTH,
                        "g_SRC_DATA_WIDTH" : g_SRC_DATA_WIDTH
                        }
                        )
vu.main()
