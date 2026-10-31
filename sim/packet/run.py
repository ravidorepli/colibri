# SPDX-FileCopyrightText: 2026 CERN
#
# SPDX-License-Identifier: CERN-OHL-W-2.0

import os
from vunit import VUnit
import itertools
import random

# test settings
n_packets = [20] # a good amount
pkt_sizes = [9000] # jumbo frame tests
data_widths = [8, 64, 256] # 256 is the limit of vvc
header_widths = [8,14,20] # common header sizes (udp, mac, ip)
    
GHDL_OPTS = ["-frelaxed", "-fsynopsys", "--syn-binding"]
NVC_A_OPTS = ["--relaxed"]
script_dir = os.path.dirname(__file__)
PROJ_ROOT = os.path.join(script_dir, "../../")

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
bitvis_vip_clock_generator_lib.add_source_files("UVVM/uvvm_vvc_framework/src_target_dependent/*.vhd")
bitvis_vip_clock_generator_lib.add_source_files("UVVM/bitvis_vip_clock_generator/src/*.vhd")

bitvis_vip_avalon_st_lib = vu.add_library('bitvis_vip_avalon_st')
bitvis_vip_avalon_st_lib.add_source_files('UVVM/uvvm_vvc_framework/src_target_dependent/*.vhd')
bitvis_vip_avalon_st_lib.add_source_files('UVVM/bitvis_vip_avalon_st/src/*.vhd')

bitvis_vip_axistream_lib = vu.add_library("bitvis_vip_axistream")
bitvis_vip_axistream_lib.add_source_files("UVVM/uvvm_vvc_framework/src_target_dependent/*.vhd")
bitvis_vip_axistream_lib.add_source_files("UVVM/bitvis_vip_axistream/src/*.vhd")

colibri_lib = vu.add_library("colibri")
colibri_lib.add_source_files(os.path.join(PROJ_ROOT, "src/common/*.vhdl"), allow_empty=True)
colibri_lib.add_source_files(os.path.join(PROJ_ROOT, "src/comms/*.vhdl"), allow_empty=True)
colibri_lib.add_source_files(os.path.join(PROJ_ROOT, "src/interfaces/stream/*.vhdl"), allow_empty=True)
colibri_lib.add_source_files(os.path.join(PROJ_ROOT, "src/misc/*.vhdl"), allow_empty=True)
colibri_lib.add_source_files(os.path.join(PROJ_ROOT, "src/memory/*.vhdl"), allow_empty=True)
colibri_lib.add_source_files(os.path.join(PROJ_ROOT, "src/memory/*/*.vhdl"), allow_empty=True)
colibri_lib.add_source_files(os.path.join(PROJ_ROOT, "src/packet/*.vhdl"), allow_empty=True)

tb_lib = vu.add_library("tb_lib")
tb_lib.add_source_files(os.path.join(PROJ_ROOT, "sim/packet/*.vhdl"), allow_empty=True)

vu.add_compile_option("ghdl.a_flags", GHDL_OPTS)
vu.add_compile_option("nvc.a_flags", NVC_A_OPTS)

for tb in tb_lib.get_test_benches():
    tb.set_sim_option("modelsim.vsim_flags.gui", ["-voptargs=+acc", "-debugdb"])
    tb.set_sim_option(
        "rivierapro.vsim_flags.gui",
        ["-voptargs=+acc", "-debugdb", "+access +r", "-advdataflow"],
    )
    tb.set_sim_option("ghdl.elab_flags", GHDL_OPTS)
    tb.set_sim_option("nvc.heap_size", "2g")
    # tb.set_sim_option("ghdl.sim_flags", ["--fst=wave.fst"])
    tb.set_sim_option("nvc.sim_flags", ["--wave=wave.fst"])
    tb.set_sim_option("disable_ieee_warnings", True)
    # tb.set_sim_option("ghdl.sim_flags", ["--assert-level=warning"])
    tests = tb.get_tests("header_random")

    for test in tests:
        print(test.name)
        
        for pkts, size, width, head in itertools.product(n_packets, pkt_sizes, data_widths, header_widths):
            test.add_config(
                name="packets=%s,size=%s,width=%s,headw=%s" % (pkts, size, width, head),
                generics=dict(
                     g_N_PACKETS=pkts, g_PACKET_SIZE=size, g_DATA_WIDTH= width, g_HEADER_BYTES=head
                ),
            )
    tests = tb.get_tests("interleave_random")
    for test in tests:
        print(test)
        for pkt in itertools.product([True, False]):
            test.add_config(
                name="words=%s" % (pkt),
                generics=dict(
                     g_INTERLEAVE_WORDS=bool(pkt)
                ),
            )

    if tb.name == "packet_join_tb":

        # some selected test scenarios
        for g_SYM_WIDTH in [1, 8, 9]:
            for g_DATA_SYM in [1, 4, 17]:
                tb.add_config(
                    name = f'swidth={g_SYM_WIDTH},dwidth={g_DATA_SYM}',
                    generics = {
                        "g_SEED"      : random.randint(1, 1024),
                        "g_SYM_WIDTH" : g_SYM_WIDTH,
                        "g_DATA_SYM"  : g_DATA_SYM
                        }
                    )
vu.main()
