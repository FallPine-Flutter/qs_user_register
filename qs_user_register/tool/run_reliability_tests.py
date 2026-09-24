# -*- coding: utf-8 -*-
"""Run private-library regression tests without adding production test hooks.

The generated library copies production source verbatim except imports/part
assembly. Platform and external information/storage APIs are replaced only in
this test library; Dio and all task/request lifecycle code remain real.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'lib/qs_user_register.dart').read_text()
for package in ['qs_ip_location', 'qs_asa_attribution_info', 'qs_device_info', 'qs_storage_tool']:
    source = source.replace("import 'package:%s/%s.dart';" % (package, package), '')
source = source.replace("import 'dart:io';", "import 'dart:io' hide Platform;")
source = source.replace("part 'src/register_task.dart';", '')
task = (root / 'lib/src/register_task.dart').read_text().replace("part of '../qs_user_register.dart';", '')
fixture = (root / 'tool/reliability_tests.dart.inc').read_text()
imports, cases = fixture.split('// END TEST IMPORTS', 1)
with tempfile.TemporaryDirectory(prefix='register_tests_', dir=root / '.dart_tool') as directory:
    target = Path(directory) / 'reliability_test.dart'
    target.write_text(imports + source + task + cases)
    result = subprocess.run(['flutter', 'test', '--no-pub', '--reporter', 'expanded', str(target)], cwd=root)
    raise SystemExit(result.returncode)
