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

#ifndef HARDWARE_SIGNAGE_DISPLAY_MAIN_H__
#define HARDWARE_SIGNAGE_DISPLAY_MAIN_H__

#define NUL 0x00  // padding to flush xbee output buffer
#define STX 0x02  // server start transfer
#define ETX 0x03  // server end transfer
#define EOT 0x04  // End of Transter (currently not used)
#define ACK 0x06  // receive success
#define NAK 0x15  // receive failure
#define SYN 0x16  // request receiving
#define CAN 0x18  // stop all communications and retry later
#define TIMING_REPORT 0x0  // Report timing information

// Failed due to not seeing CAN, STX, or ETX as the header byte
#define FAIL_NO_HEADER 0
// Failed due to buffer overrun in UART reception
#define FAIL_OVERRUN 1


#endif  // HARDWARE_SIGNAGE_DISPLAY_MAIN_H__
