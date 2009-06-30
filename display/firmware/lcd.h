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

#ifndef HARDWARE_SIGNAGE_DISPLAY_LCD_H__
#define HARDWARE_SIGNAGE_DISPLAY_LCD_H__

#define LCD_RESET  RC1
#define LCD_BUSY   RC2
#define LCD_CS     RC3
#define LCD_PUMP   RC4

// Function Prototypes
extern void clr_disp_brt(void);
extern void clr_disp_drk(void);

extern void lcdstartcmd(void);
extern void lcdendcmd(void);
extern void lcdsend(unsigned char);
extern void lcd_disp_fullscrn(void);
extern void lcd_sleep(void);

#endif  // HARDWARE_SIGNAGE_DISPLAY_LCD_H__
