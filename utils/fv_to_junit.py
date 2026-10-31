# SPDX-FileCopyrightText: 2026 CERN
#
# SPDX-License-Identifier: CERN-OHL-W-2.0

import sys
import csv
import argparse
import xml.etree.ElementTree as ET
from collections import defaultdict

def parse_csv(stdin):
    suites = defaultdict(list)
    reader = csv.DictReader(stdin)
    for row in reader:
        suites[row["task_name"]].append(row)
    return suites

def parse_plain(stdin):
    suites = defaultdict(list)
    for line in stdin:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        full_name, status = parts[0], parts[1]
        if '.' in full_name:
            suite_name, case_name = full_name.split('.', 1)
        else:
            suite_name, case_name = "default", full_name
        suites[suite_name].append({"name": case_name, "status": status, "time": "0"})
    return suites

def build_xml(suites, is_csv):
    testsuites = ET.Element("testsuites")
    for suite_name, cases in suites.items():
        testsuite = ET.SubElement(
            testsuites,
            "testsuite",
            name=suite_name,
            tests=str(len(cases)),
            failures=str(sum(1 for c in cases if (c["status"] if is_csv else c["status"]) != "PASS")),
        )
        for case in cases:
            testcase = ET.SubElement(
                testsuite,
                "testcase",
                classname=suite_name,
                name=case["name"],
                time=case.get("time", "0"),
            )
            if case["status"] != "PASS":
                failure = ET.SubElement(testcase, "failure", message=case["status"])
                failure.text = case.get("trace", "")
    return testsuites

def indent(elem, level=0):
    i = "\n" + level * "  "
    if len(elem):
        if not elem.text or not elem.text.strip():
            elem.text = i + "  "
        for e in elem:
            indent(e, level + 1)
        if not e.tail or not e.tail.strip():
            e.tail = i
    if level and (not elem.tail or not elem.tail.strip()):
        elem.tail = i

def main():
    parser = argparse.ArgumentParser(description="Convert test report to JUnit XML")
    parser.add_argument("--csv", action="store_true", help="Input is CSV format")
    args = parser.parse_args()

    if args.csv:
        suites = parse_csv(sys.stdin)
    else:
        suites = parse_plain(sys.stdin)

    testsuites = build_xml(suites, is_csv=args.csv)
    indent(testsuites)
    tree = ET.ElementTree(testsuites)
    tree.write(sys.stdout, encoding="unicode", xml_declaration=True)

if __name__ == "__main__":
    main()