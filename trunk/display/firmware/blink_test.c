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
#include "pause.h"
#include "init.h"

__IDLOC(1);
__CONFIG(INTIO & WDTDIS & MCLREN & BORDIS & UNPROTECT & PWRTEN);

void main(void) {
  init_all();

  // Blink at 25Hz. That should be slow enough to tell that it's blinking with
  // the naked eye, fast enough to measure quickly, and slow enough to swamp
  // other timing issues.
  while (1) {
    pause_msec(20);
    RA5 = 1;
    pause_msec(20);
    RA5 = 0;
  }
}
