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

#include "lcd.h"

void lcdsend(unsigned char segment) {
  while (!BF);  // wait until previous data is sent
  SSPBUF = segment;
}

void lcdstartcmd(void) {
  while (LCD_BUSY);
  LCD_CS = 0;
}

void lcdendcmd(void) {
  while (!BF);  // wait for byte to finish sending
  LCD_CS = 1;
}

void clr_disp_brt(void){
  lcdstartcmd();
  lcdsend(0x10);
  lcdendcmd();
}

void clr_disp_drk(void) {
  lcdstartcmd();
  lcdsend(0x12);
  lcdendcmd();
}

void lcd_sleep(void) {
  lcdstartcmd();
  lcdsend(0x20);
  lcdendcmd();
}

void lcd_disp_fullscrn(void) {
  // Display Fullscreen
  lcdstartcmd();
  lcdsend(0x18); // DISP_FULLSCRN
  lcdsend(0);
  lcdsend(0);
  lcdendcmd();
}
