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

#ifndef HARDWARE_SIGNAGE_DISPLAY_INIT_H__
#define HARDWARE_SIGNAGE_DISPLAY_INIT_H__

// No real good place to put this.
#define LED            RA5
#define TS_POWER       RC5
#define TS_OUTPUT      RC6
#define TS_OUTPUT_TRIS TRISC6
#define TS_OUTPUT_ANS  ANS8

#define BIT_SET(reg, bit)   ((reg) |= 1UL << (bit))
#define BIT_CLEAR(reg, bit) ((reg) &= ~(1UL << (bit)))

void init_ports(void);
void lcd_init(void);
void radio_init(void);
void init_all(void);

#endif  // HARDWARE_SIGNAGE_DISPLAY_INIT_H__
