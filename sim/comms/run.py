# SPDX-FileCopyrightText: 2026 CERN
#
# SPDX-License-Identifier: CERN-OHL-W-2.0

import os
from vunit import VUnit
import itertools

GHDL_OPTS = ["-frelaxed", "-fsynopsys", "--syn-binding"]
NVC_A_OPTS = ["--relaxed"]
script_dir = os.path.dirname(__file__)
PROJ_ROOT = os.path.join(script_dir, "../../")
# loopback test settings
a_widths = [16, 32]
b_widths = range(1, 129)

# bert settings
bert_dwidth = [4, 8, 16, 32, 64]
bert_delay = range(1, 20)

# crc settings
crc_dwidth = [16, 32, 64]
crc_polys = [("7", 8), ("1021", 16), ("04c11db7", 32)]

vu = VUnit.from_argv()
vu.add_vhdl_builtins()
vu.add_osvvm()
vu.add_verification_components()

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
tb_lib.add_source_files(os.path.join(PROJ_ROOT, "sim/comms/*.vhdl"), allow_empty=True)

vu.add_compile_option("ghdl.a_flags", GHDL_OPTS)
vu.add_compile_option("nvc.a_flags", NVC_A_OPTS)
for tb in tb_lib.get_test_benches():
    tb.set_sim_option("modelsim.vsim_flags.gui", ["-voptargs=+acc", "-debugdb"])
    tb.set_sim_option(
        "rivierapro.vsim_flags.gui",
        ["-voptargs=+acc", "-debugdb", "+access +r", "-advdataflow"],
    )
    tb.set_sim_option("ghdl.elab_flags", GHDL_OPTS)
    tb.set_sim_option("nvc.sim_flags", ["-wwave.fst", "--dump-arrays"])
    tb.set_sim_option("nvc.heap_size", "256m")
    tb.set_sim_option("disable_ieee_warnings", True)
    # tb.set_sim_option("ghdl.sim_flags", ["--assert-level=warning"])
    tests = tb.get_tests("*loopback*")
    for test in tests:
        for a, b in itertools.product(a_widths, b_widths):
            test.add_config(
                name="a_width=%s,b_width=%s" % (a, b),
                generics=dict(g_A_WIDTH=a, g_B_WIDTH=b),
            )

    tests = tb.get_tests("*bert*")
    for test in tests:
        for width, delay in itertools.product(bert_dwidth, bert_delay):
            test.add_config(
                name="dwidth=%s,delay=%s" % (width, delay),
                generics=dict(g_DATA_WIDTH=width, g_DUT_DELAY=delay),
            )
            tests = tb.get_tests("*bert*")

    tests = tb.get_tests("*crc*")
    for test in tests:
        for refin, refout in itertools.product([False, True], [False, True]):
            test.add_config(
                name="refin=%s,refout=%s" % (refin, refout),
                generics=dict(g_INVERT_IN=refin, g_INVERT_OUT=refout),
            )

        for width, crc in itertools.product(crc_dwidth, crc_polys):
            test.add_config(
                name="dwidth=%s,crc=%s" % (width, crc),
                generics=dict(
                    g_DATA_WIDTH=width,
                    g_CRC_POLY_STRING=crc[0],
                    g_CRC_POLY_LENGTH=crc[1],
                ),
            )

    if tb.name == "bit_shifter_tb":
        for width, msb_right in itertools.product(
            [8, 11, 32, 43, 64, 97, 128], [True, False]
        ):
            tb.add_config(
                name=f"dwidth={width},msb_right={msb_right}",
                generics=dict(g_DATA_WIDTH=width, g_MSB_RIGHT=msb_right),
            )
vu.main()
