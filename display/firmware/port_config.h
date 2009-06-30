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

#ifndef HARDWARE_SIGNAGE_DISPLAY_PORT_CONFIG_H__
#define HARDWARE_SIGNAGE_DISPLAY_PORT_CONFIG_H__

#define LOW  0
#define HIGH 1
#define TRIS 0x100

// First argument is a port number, i.e. RA5 without the RA.
// Second argument is an initial state, one of the three above.
// Third argument is unused, but meant for a description of that pin.
#define BIT_INIT(bit, state, desc)\
  ((state) << (bit)) |

// First argument is a letter, i.e. B for PORTB. (No quotes!)
// Second argument is a list of BIT_INITS above. They concatenate
// automatically.
// Setting PORT before TRIS so that we don't have a 1usec "blip" of outputting
// the wrong value.
#define PORT_INIT(port, state)\
  PORT##port = (state 0) & 0xff;\
  TRIS##port = (state 0) >> 8

#endif  // HARDWARE_SIGNAGE_DISPLAY_PORT_CONFIG_H__
