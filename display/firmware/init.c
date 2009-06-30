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

#include "init.h"
#include "lcd.h"
#include "port_config.h"

#define BAUD 57600
#define XTAL_FREQ 4000
#define BPS(x) (int)((XTAL_FREQ) *250.0 /(x) -0.5 )

// sets up all the ports in a sane manner
void init_ports(void) {
  PORT_INIT(A,\
    BIT_INIT(0,  LOW, ICSP Data)\
    BIT_INIT(1, HIGH, ICSP Clock)\
    BIT_INIT(2, TRIS, Vcap)\
    BIT_INIT(3,  LOW, Vpp)\
    BIT_INIT(4, TRIS, Button)\
    BIT_INIT(5,  LOW, LED)\
  );

  PORT_INIT(B,\
    BIT_INIT(4, TRIS, LCD SDI)\
    BIT_INIT(5, TRIS, XBee RX)\
    BIT_INIT(6,  LOW, LCD Clock)\
    BIT_INIT(7, HIGH, XBee TX)\
  );

  PORT_INIT(C,\
    BIT_INIT(0, HIGH, XBee Sleep)\
    BIT_INIT(1, HIGH, LCD /Reset)\
    BIT_INIT(2, TRIS, LCD Busy)\
    BIT_INIT(3, HIGH, LCD /CS)\
    BIT_INIT(4,  LOW, +5V pump enable)\
    BIT_INIT(5,  LOW, Temperature sensor power)\
    BIT_INIT(6,  LOW, Temperature sensor output)\
    BIT_INIT(7,  LOW, LCD SDO)\
  );

  ANSEL = 0x04; // ANS2 (RA2, VCAP) is analog...
  ANSELH = 0x00; // ...rest is digital
  ADCON0 = 0b00001000; // ADC Left justified, using Vdd, AN2, Powered Down
  ADCON1 = 0x10; // AD Scaling is Fosc/8

  // Disable internal pull-ups
  OPTION = 0x80;

  // GIE is off, so this won't cause actual interrupts. It'll only wake from
  // sleep.
  IOCA4 = 1;  // Enable interrupt-on-change for RA4 (Button)
  RABIE = 1;  // Enable interrupt-on-change flag
}

void lcd_init(void) {
  LCD_RESET = 0; // Start Reset on LCD

  // Enable SPI Master mode
  // Idle clock is low, 250kHz FOSC/16, Enable
  SSPCON = 0b00100001;

  NOP(); // Need to ensure that RESET is held for > 2us
  LCD_RESET = 1;  // done asserting RESET pin

  // Send a dummy byte, to fill the recieve buffer. This is the only way we
  // can tell when send sending byte is fully sent.
  SSPBUF = 0;
}

void radio_init(void) {
  // Setup Baud Rate
  SYNC = 0;
  BRGH = 1;
  BRG16 = 1;
  SPBRG  = BPS(BAUD) & 0xff;
  SPBRGH = BPS(BAUD) >> 8;

  // Enable Transmit, Receive, Async Serial
  CREN = 1;
  TXEN = 1;
  SPEN = 1;
}

void init_all(void) {
  init_ports();
  lcd_init();
  radio_init();
}
