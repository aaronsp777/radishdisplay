/*
Copyright 2009 Google Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

#include <pic.h>

// Assuming 1 MIPS clock speed, constant needs tweaking otherwise.
void pause_msec(unsigned count) {
  for (; count != 0; count--) {
    // The inner loop burns 4 cycles per iteration, however there's 12 extra
    // cycles of overhead dealing with the outer loop, so we shave off three
    // iterations to make it even. Watch out, this is *VERY* sensitive to
    // compiler/optimization settings.
    unsigned char inner_count = 247;
    for (; inner_count != 0; inner_count--) {
      asm("nop");
    }
  }
}
