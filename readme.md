<!--
SPDX-FileCopyrightText: 2026 CERN

SPDX-License-Identifier: Apache-2.0
-->

![logo](docs/logo/colibri_small_docs.png)
## Open Source, Vendor Independent VHDL Common Library

This library is a collection of common components, functions, and procedures used in CERN gateware projects.
The scope of the library is to simplify and standardise the development of gatewares for CERN.

## Structure
 - [colibri.common](src/common/readme.md) Common Functions
 - [colibri.comms](src/comms/readme.md) Utilities for Communications (PRBS, CRC, ...)
 - [colibri.endec](src/endec/readme.md) Encoders and Decoders (RLE, 8b10b, ...)
 - [colibri.fileio](src/fileio/readme.md) File Operations
 - [colibri.interfaces](src/interfaces/readme.md) Bus and Stream Protocols Components (AXI, Avalon, Wishbone, ...)
 - [colibri.io](src/io/readme.md) Input Output protocols (UART, I2C, SPI, ...)
 - [colibri.memory](src/memory/readme.md) Memory Entities (FIFOs, RAMs)
 - [colibri.misc](src/misc/readme.md) Miscellaneous
 - [colibri.pipes](src/pipes/readme.md) Pipes entities (Arbiter, Router, ...)
 - [colibri.packet](src/packet/readme.md) Manipulation of Packeted streams
 - [colibri.proto](src/proto/readme.md) Protocols (Aurora 64b66b, ...)

Everything in this repository should be compiled under `colibri` library.

Testbenches are available in the [sim](sim) directory, formal verification tests are available in the [fv](fv) directory.

### How to use
To use colibri, just import the `vhdl` files in your project and compile them under the `colibri` library as VHDL 2008.  
To simplify integration, file lists are available:
- **Hog**:  
    add the [utils/hog/colibri.src](utils/hog/colibri.src) to your `hog.conf`.
- **FuseSoC**:  
    Run `fusesoc library add colibri https://gitlab.cern.ch/colibri/colibri.git --sync-type=git` if you want to use git.  
    Run `fusesoc library add colibri <path_to_colibri> --sync-type=local` if you have a local copy.
- **Vivado**:  
    In the Tcl Console, run `source <path_to_colibri>/utils/vivado/colibri.tcl`.  
    **NOTE** For older Vivado versions, you may want to use the legacy tcl file `source <path_to_colibri>/utils/vivado/colibri_legacy.tcl`.
    Refer to colibri/colibri#8
- **Quartus**:  
    In the Tcl Console, run `source <path_to_colibri>/utils/quartus/colibri.tcl`.  
    **NOTE** For Quartus Standard versions before 23.1, use the legacy tcl file `source <path_to_colibri>/utils/quartus/colibri_legacy.tcl`. Refer to colibri/colibri#8

### License
The content of this repository is licensed under CERN-OHL-W-2.0, if another license is not specified.
All used licenses are available under [LICENSES](./LICENSES/).

### How to contribute

Contributing in the form of code, feedback, ideas or bug reports are welcome. Code contributions are expected to have self-checking testbenches, formal verification tests, and pass the style checks. If there are any problems let us know.

Before doing any major changes we recommend creating an issue or chatting with us on mattermost to discuss first. In this way you do not get started on the wrong track and waste time.

### Talks and Workshops
- [*colibri: An Open Source, Vendor Agnostic VHDL Common Library*, Alberto Perro, Topical Workshop on Electronics for Particle Physics, Glasgow, 2/10/2024.](https://indi.to/jsW6K)
- [*colibri: Towards a CERN-wide common cores library*, Alberto Perro, FPGA Developers' Forum, CERN, 11/06/2024.](https://indi.to/fYDfT) See the video recording [here](https://youtu.be/vGB1HCiTr_s?si=CYyaLwIjkOrEJiXV).
- [*colibri formal verification*, Alberto Perro, CERN Electronics Forum, 03/04/2025.](https://indico.cern.ch/event/1529176/)
- [*Hands-on: DAQ Firmware Design with the colibri VHDL library*, Mitja Vodnik, FPGA Developers' Forum, CERN, 29/05/2026](https://indico.cern.ch/event/1688253/)

### Maintainers
@alperro alberto.perro (at) cern.ch **Corresponding Author**  
@mvodnik mitja.vodnik (at) cern.ch

### Contributors
@cgentsos
@mderen
@pdurante