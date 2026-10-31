# SPDX-FileCopyrightText: 2026 CERN
#
# SPDX-License-Identifier: CERN-OHL-W-2.0

import os
import glob
from vunit import VUnit
from systemrdl import RDLCompiler, RDLCompileError
from peakrdl_regblock_vhdl import RegblockExporter
from peakrdl_regblock_vhdl.cpuif.passthrough import PassthroughCpuif
from peakrdl_regblock_vhdl.udps import ALL_UDPS

def exportVHDL(path, outdir):
    rdlc = RDLCompiler()
    for udp in ALL_UDPS:
        rdlc.register_udp(udp)
    try:
        srcfiles = glob.glob(path)
        for input_file in srcfiles:
            rdlc.compile_file(input_file)
        root = rdlc.elaborate()
    except RDLCompileError:
        exit(1)
    exporter = RegblockExporter()
    exporter.export(root, outdir,cpuif_cls=PassthroughCpuif,address_width=32,copy_utils_pkg=True)

GHDL_OPTS = ["-frelaxed","-fsynopsys", "--syn-binding"]
NVC_A_OPTS = ["--relaxed"]
script_dir = os.path.dirname(__file__)
PROJ_ROOT = os.path.join(script_dir,"../../")

vu = VUnit.from_argv()
vu.add_vhdl_builtins()
vu.add_verification_components()
vu.add_osvvm()

uvvm_util_lib = vu.add_library('uvvm_util')
uvvm_util_lib.add_source_files('UVVM/uvvm_util/src/*.vhd')

uvvm_vvc_framework_lib = vu.add_library('uvvm_vvc_framework')
uvvm_vvc_framework_lib.add_source_files('UVVM/uvvm_vvc_framework/src/*.vhd')

bitvis_vip_scoreboard_lib = vu.add_library('bitvis_vip_scoreboard')
bitvis_vip_scoreboard_lib.add_source_files('UVVM/bitvis_vip_scoreboard/src/*.vhd')

bitvis_vip_clock_generator_lib = vu.add_library('bitvis_vip_clock_generator')
bitvis_vip_clock_generator_lib.add_source_files('UVVM/uvvm_vvc_framework/src_target_dependent/*.vhd')
bitvis_vip_clock_generator_lib.add_source_files('UVVM/bitvis_vip_clock_generator/src/*.vhd')

bitvis_vip_avalon_st_lib = vu.add_library('bitvis_vip_avalon_st')
bitvis_vip_avalon_st_lib.add_source_files('UVVM/uvvm_vvc_framework/src_target_dependent/*.vhd')
bitvis_vip_avalon_st_lib.add_source_files('UVVM/bitvis_vip_avalon_st/src/*.vhd')

bitvis_vip_wishbone_lib = vu.add_library('bitvis_vip_wishbone')
bitvis_vip_wishbone_lib.add_source_files('UVVM/uvvm_vvc_framework/src_target_dependent/*.vhd')
bitvis_vip_wishbone_lib.add_source_files('UVVM/bitvis_vip_wishbone/src/*.vhd')

colibri_lib = vu.add_library('colibri')
colibri_lib.add_source_files(os.path.join(PROJ_ROOT,"src/common/*.vhdl") ,allow_empty=True)
colibri_lib.add_source_files(os.path.join(PROJ_ROOT,"src/comms/*.vhdl") ,allow_empty=True)
colibri_lib.add_source_files(os.path.join(PROJ_ROOT,"src/misc/*.vhdl") ,allow_empty=True)
colibri_lib.add_source_files(os.path.join(PROJ_ROOT,"src/memory/*.vhdl") ,allow_empty=True)
colibri_lib.add_source_files(os.path.join(PROJ_ROOT,"src/memory/*/*.vhdl") ,allow_empty=True)
for file in glob.glob(os.path.join(PROJ_ROOT,"src/misc/mmap_fifo/*.rdl")):
    exportVHDL(file,os.path.join(PROJ_ROOT,"src/misc/mmap_fifo/vhdl_if"))
colibri_lib.add_source_files(os.path.join(PROJ_ROOT,"src/misc/mmap_fifo/vhdl_if/*.vhd"))
colibri_lib.add_source_files(os.path.join(PROJ_ROOT,"src/misc/mmap_fifo/*.vhdl") ,allow_empty=True)

tb_lib = vu.add_library("tb_lib")
tb_lib.add_source_files(os.path.join(PROJ_ROOT,"sim/misc/*/*.vhdl") ,allow_empty=True)
tb_lib.add_source_files(os.path.join(PROJ_ROOT,"sim/misc/*.vhdl") ,allow_empty=True)

vu.add_compile_option("ghdl.a_flags",GHDL_OPTS )
vu.add_compile_option("nvc.a_flags",NVC_A_OPTS )
for tb in tb_lib.get_test_benches():
    tb.set_sim_option("modelsim.vsim_flags.gui", ["-voptargs=+acc","-debugdb"])
    tb.set_sim_option("rivierapro.vsim_flags.gui", ["-voptargs=+acc","-debugdb", "+access +r", "-advdataflow"])
    tb.set_sim_option("ghdl.elab_flags", GHDL_OPTS)
    tb.set_sim_option("nvc.heap_size", "256m")
    tb.set_sim_option("nvc.sim_flags", ["--wave=wave.fst","--dump-arrays"])
    tb.set_sim_option("disable_ieee_warnings", True)
    # tb.set_sim_option("ghdl.sim_flags", ["--assert-level=warning"])
vu.main()