<!--
SPDX-FileCopyrightText: 2026 CERN

SPDX-License-Identifier: CERN-OHL-W-2.0
-->

# Automated Resource Scan Script 

This `tcl` script is an automatic generator of compilation flavors based on Quartus.

## Configuration

The script uses the `config.json` configuration file in this folder.  
In this file, you can specify the device part number, top level entity, and generics.
```json
{
    "device" : "10AX115S3F45E2SG",
    "top" : "header_remove",
    "g_DATA_WIDTH" : [8, 16, 32],
    "g_HEADER_BYTES" : [3, 5, 8]
}
```
The script will automatically generate compilations for each generic combinations.

## Running
The script can be run using:
```
,path-to-your-quartus-install>/quartus_sh -t scan.tcl
```

## Results
Results are logged in the `results_<top-name>/resources_<top-name>.csv` file.
Each line of the table reports the generics configuration used, the resource usage (FF, LUT, RAM, DSP).

All Quartus logs are saved in the same result folder for further inspection.