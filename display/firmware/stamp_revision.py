#!/usr/bin/python2.4
#
# Copyright 2009 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


"""Extracts a revision string from stdin, and writes a header to stdout.

The generated header file defines two macro constants so that the compilied
code can be better optimized. These bytes are sent over the wire to identify
the firmware revision. The IDLOC macro programs the ID location in the pic,
which can be read by programmers and debuggers.
"""

import sre
import struct
import sys

# Example: "// $Revision: #5 $"
pattern = sre.compile(".*\\$Revision:\\s*#(\\d+)\\s*\\$")
revision = -1

for line in sys.stdin:
  match = pattern.match(line)
  if match:
    # Add one, because that's the revision it'll be when committed
    revision = int(match.group(1)) + 1

revision_string = struct.pack("<h", revision)
output = """
#ifndef HARDWARE_SIGNAGE_DISPLAY_REVISION_H__
#define HARDWARE_SIGNAGE_DISPLAY_REVISION_H__

#include <pic.h>

#define REVISION_LOW  %d
#define REVISION_HIGH %d

__IDLOC(%04X);

#endif  // HARDWARE_SIGNAGE_DISPLAY_REVISION_H__
""" % (ord(revision_string[0]), ord(revision_string[1]), revision)

sys.stdout.write(output)
