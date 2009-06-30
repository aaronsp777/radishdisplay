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
#include "main.h"

#define RADIO_SLEEP RC0
void putc(unsigned char c){
  while (!TXIF); // Wait until output buffer is available
  TXREG = c;
}

// blocks
unsigned char getc(void){
  while(!RCIF); // Wait until we have a char
  // Turn off the led when we get a byte. This allows us to quickly
  // see the round trip time for a packet, and it saves energy.
  CLRWDT();
  return RCREG;
}

// set to 1 to sleep, 0 to wake
void radio_sleep(void){
  while (!TRMT); // Wait until output buffer is eMpTy
  RADIO_SLEEP = 1;
  SPEN = 0;
}

void radio_wake(void){
  SPEN = 1;
  RADIO_SLEEP = 0;
  // require 13.2mS to wake up from Sleep Mode 1, 2mS for SM2
  // TODO: We could also wait for /CTS to go low, this would require a
  // hardware change.
  pause_msec(15);
}
