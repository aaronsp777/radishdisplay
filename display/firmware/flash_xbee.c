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
/* Code that simply holds the DTR line low so that the XBEE can be flashed on-board */

#include <pic.h>

#include "init.h"

__IDLOC(9999);
__CONFIG(INTIO & WDTDIS & MCLRDIS & BORDIS & UNPROTECT & PWRTEN);

void main(void){
  init_all();

  // Cede control of the XBee to the external line
  SPEN = 0;
  TRISB7 = 1;  // Tristate XBee TX so we don't fight for it

  // TURN LED on
  RA5 = 1;

  // Turn radio on
  // DTR is mapped to RC0
  RC0 = 0;

  // Do nothing else
  while(1) {
    SLEEP();
  }
}
