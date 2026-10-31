# SPDX-FileCopyrightText: 2026 CERN
#
# SPDX-License-Identifier: CERN-OHL-W-2.0

import os
from vunit import VUnit
import itertools

# test settings
data_widths = [8, 16, 32]
num_lanes = range(1, 5)


GHDL_OPTS = ["-frelaxed", "-fsynopsys", "--syn-binding"]
NVC_A_OPTS = ["--relaxed"]
script_dir = os.path.dirname(__file__)
PROJ_ROOT = os.path.join(script_dir, "../../../")

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

colibri_lib = vu.add_library("colibri")
colibri_lib.add_source_files(
    os.path.join(PROJ_ROOT, "src/common/*.vhdl"), allow_empty=True
)
colibri_lib.add_source_files(
    os.path.join(PROJ_ROOT, "src/memory/*.vhdl"), allow_empty=True
)
colibri_lib.add_source_files(
    os.path.join(PROJ_ROOT, "src/memory/*/*.vhdl"), allow_empty=True
)
colibri_lib.add_source_files(
    os.path.join(PROJ_ROOT, "src/comms/*.vhdl"), allow_empty=True
)
colibri_lib.add_source_files(
    os.path.join(PROJ_ROOT, "src/proto/aurora_64b66b/*.vhdl"), allow_empty=True
)
colibri_lib.add_source_files(
    os.path.join(PROJ_ROOT, "src/proto/aurora_64b66b/rx/*.vhdl"), allow_empty=True
)
colibri_lib.add_source_files(
    os.path.join(PROJ_ROOT, "src/proto/aurora_64b66b/tx/*.vhdl"), allow_empty=True
)
colibri_lib.add_source_files(
    os.path.join(PROJ_ROOT, "src/proto/aurora_64b66b/include/*.vhdl"), allow_empty=True
)

tb_lib = vu.add_library("tb_lib")
tb_lib.add_source_files(
    os.path.join(PROJ_ROOT, "sim/proto/aurora_64b66b/tx/*.vhdl"), allow_empty=True
)
tb_lib.add_source_files(
    os.path.join(PROJ_ROOT, "sim/proto/aurora_64b66b/rx/*.vhdl"), allow_empty=True
)
tb_lib.add_source_files(
    os.path.join(PROJ_ROOT, "sim/proto/aurora_64b66b/endec/*.vhdl"), allow_empty=True
)
tb_lib.add_source_files(
    os.path.join(PROJ_ROOT, "sim/proto/aurora_64b66b/loopback/*.vhdl"), allow_empty=True
)
tb_lib.add_source_files(
    os.path.join(PROJ_ROOT, "sim/proto/aurora_64b66b/throughput/*.vhdl"), allow_empty=True
)
tb_lib.add_source_files(
    os.path.join(PROJ_ROOT, "sim/proto/aurora_64b66b/*.vhdl"), allow_empty=True
)

vu.add_compile_option("ghdl.a_flags", GHDL_OPTS)
vu.add_compile_option("nvc.a_flags", NVC_A_OPTS)

for tb in tb_lib.get_test_benches():
    tb.set_sim_option("modelsim.vsim_flags.gui", ["-voptargs=+acc", "-debugdb"])
    tb.set_sim_option(
        "rivierapro.vsim_flags.gui",
        ["-voptargs=+acc", "-debugdb", "+access +r", "-advdataflow"],
    )
    tb.set_sim_option("ghdl.elab_flags", GHDL_OPTS)
    tb.set_sim_option("nvc.heap_size", "256m")
    # tb.set_sim_option("ghdl.sim_flags", ["--fst=wave.fst"])
    tb.set_sim_option("nvc.sim_flags", ["--wave=wave.fst", "--dump-arrays"])
    tb.set_sim_option("disable_ieee_warnings", True)
    # tb.set_sim_option("ghdl.sim_flags", ["--assert-level=warning"])
    tests = tb.get_tests("*loopback*")
    for test in tests:
        for width, lane in itertools.product(data_widths, num_lanes):
            test.add_config(
                name="data_width=%s,lanes=%s" % (width, lane),
                generics=dict(g_LANE_WIDTH=width, g_NUM_LANES=lane),
            )
    if tb.name == 'aurora_throughput_tb':
        for width, lane in itertools.product(data_widths, num_lanes):
            tb.add_config(
                name="data_width=%s,lanes=%s" % (width, lane),
                generics=dict(g_LANE_WIDTH=width, g_N_LANES=lane),
            )
vu.main()
