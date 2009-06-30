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
#include "xbee.h"
#include "main.h"
#include "pause.h"
#include "revision.h"

// $Revision: #23 $

__CONFIG(INTIO & WDTDIS & MCLREN & BORDIS & UNPROTECT & PWRTEN);

// These global variables are written at various points in do_radio_stuff
// setup_sleeptime uses exponent.
unsigned char sleep_count;
unsigned char exponent;
unsigned char cap_voltage;
unsigned char temperature;
unsigned char button_status;
unsigned char seq_num;
#ifdef DEBUG
bit updating;
#endif

// Check voltage on some pin
// pin is specified as bits 5-2 in ADCON0. See the datasheet.
// left vs. right justified is specified as bit 7.
unsigned char read_analog(unsigned char options) {
  // using Vref, Powered up
  ADCON0 = 0b01000001 | options;

  // Toggle the temperature sensor output briefly low. If there's no sensor,
  // this will cause the next sample to read low. If there is a sensor, the
  // NOPs give it time to recharge the sample cap.
  // It's kind of a kludge that we do this on all A/D conversions, not just
  // temp sensor ones.
  TS_OUTPUT = 0;
  TS_OUTPUT_TRIS = 0;
  TS_OUTPUT_TRIS = 1;

  // Wait 8uS for the sample cap to (dis)charge
  NOP(); NOP(); NOP(); NOP();
  NOP(); NOP(); NOP(); NOP();

  // Start the sample and wait until done (aprox 20uS)
  // This can't be done in the same instruction that turns on the A/D
  for (GODONE = 1; GODONE;);

  // IMPORTANT: VCFG must be set to Vdd here, or Vref will get pulled low!
  ADCON0 = 0b00001000; // ADC Left justified, using Vdd, AN2, Powered down
  if (options & 0b10000000) {
    return ADRESL; // High order bit set = right justified = low result register
  } else {
    return ADRESH;
  }
}

void temp_sensor_on(void) {
  TS_POWER = 1; // Power up the sensor
  TS_OUTPUT_ANS = 1; // ANS8 = ANSELH[0] = RC6 analog select
  TS_OUTPUT_TRIS = 1; // Un-drive the sensor output.
}

// Bring down the sensor. This should leave everything in a safe state, even
// for older boards that don't have the sensor.
void temp_sensor_off(void) {
  // Power down. NOTE: It is vital that this be done as one atomic operation.
  // Since both the output and the power line are being driven high, (the first
  // by the sensor, the second by the capacitor on the power line,) if this is
  // done as two bit-change operations the first one will be ignored due to
  // the read-modify-write aspect of bit ops. (The read will read HIGH despite
  // being driven low by the PIC.)
  PORTC &= 0b10011111; // RC5 and RC6 are set low.
  TS_OUTPUT_TRIS = 0; // Drive sensor output low.
  // Back to digital I/O mode. (This should be done *after* driving the port,
  // in order to prevent excessive current draw from an invalid voltage input
  // level. It's only for a microsecond, but every bit helps.)
  TS_OUTPUT_ANS = 0;
}

void send_hello(void) {
  putc(SYN);
  putc(REVISION_HIGH);
  putc(REVISION_LOW);
  putc(cap_voltage);

  // Note: The expansion is on PORTC, so it can't be used to wake the radish
  // from sleep. We'll poll it here anyway.
  if (RA4)  // App button
    BIT_SET(button_status, 0);
  // Expansion pins used to go here, but they're used for the temp sensor now.

  putc(button_status);
  button_status = 0;  // Reset all bits to prepare for next round

  putc(seq_num - 1);  // Last packet received
  putc(temperature);
}

void send_ack(void) {
  putc(ACK);
  putc(0);
  putc(0);
  radio_sleep();
}

void send_nak(unsigned char failure_mode) {
  putc(NAK);
  putc(seq_num - 1);  // Last packet received
  putc(failure_mode);
  radio_sleep();
}

// returns 1 if transfer was ok
// returns 0 if transfer failed and needs to be retried
// Might also reset if the transfer failed...
//
// Protocol format:
// cancel =        {CAN sleep_bytes}
// normal packet = {STX sequence_byte command_length data...}
// last packet =   {ETX sequence_byte command_length data... sleep_bytes}
// command_length is the number of bytes in the data that follows. This is the
// same as the number of bytes to hold /CS low for.
// sequence_byte is a normal sequence number. (This means there can only be
// 256 packets, but a full screen update only takes 104.) The sequence number
// increases by one for each packet, starting at 0. If a packet is recieved
// out-of-sequence (either too high or too low), it is silently dropped on the
// floor. The underlying XBee protocol has ACKs, so the server is aware if
// packets are lost, and retries the stream from the lost packet.
bit do_radio_stuff(void) {
  unsigned len;
  unsigned char header;
  unsigned char command_len;
  unsigned char seq_num_got;
  // The compiler forces this to be static, but it doesn't change how the bit
  // is used.
  static bit ok_to_write;

#ifdef DEBUG
  // Clear the LCD memory. This takes place internal to the display's RAM, so
  // it should be fast (and finished by the time we need to send more
  // commands.)
  lcdstartcmd();
  lcdsend(0x01);  // Command
  lcdsend(0x00);  // Address High
  lcdsend(0x00);  // Address Low
  lcdsend((320*240/8-1) >> 8);    // End High
  lcdsend((320*240/8-1) & 0xff);  // End Low
  lcdsend(0xff);  // Fill value
  lcdendcmd();
#endif

  radio_wake();
  send_hello();
  LED = 1;

  seq_num = 0;

  // Set a WDT timeout of ~132 msec. If we reset because of it, we'll retry
  // with a higher sleep time beforehand.
  //
  // Note that this is weird: Experiments confirm that the round-trip time on
  // a packet doesn't exceed 62 msec, so we should be able to use a smaller
  // prescaler value. However, if you try that you'll get a bunch of resets
  // and very little correct communication with the server. Something doesn't
  // add up...
  //
  // getc() clears the WDT.
  WDTCON = 0x10;  // 1:4096 prescaler, WDT disabled
  OPTION = 0x80;  // Disable pull-ups, prescaler is on TMR0
  SWDTEN = 1;     // The clock is ticking...

  // Find out how long the request-response time is, and report it back to the
  // server.
  len = 0;
  while (!RCIF)
    len++;

  CLRWDT();
  putc(TIMING_REPORT);
  putc(len >> 8);
  putc(len);

  while (1) {
    // Save a little current until the next packet shows up.
    // The display wakes up so fast that this is worth it.
    lcd_sleep();

    // look for STX char
    header = getc();
    LED = 0;

    if (header == CAN) {
      sleep_count = getc();
      exponent = getc();
      return 1; // go back to sleep
    }

    if (header != STX && header != ETX) {
      // Garbage start - fail
      send_nak(FAIL_NO_HEADER);
      return 0;
    }

    // Recieve overflow - generally happens if the display takes too long to
    // do something. An overflow is especially insidious because the PIC has a
    // two byte FIFO buffer, and doesn't recieve anything while those are
    // full. This means that the first two bytes (STX and the sequence number)
    // will be stored, and it will look like a valid packet to the radish!
    if (OERR) {
      send_nak(FAIL_OVERRUN);
      return 0;
    }

#ifdef DEBUG
    updating = 1;
#endif

    seq_num_got = getc();
    // Ignore (i.e. don't send to the screen) any packets that are out of
    // order. We'll wait for the server to resend the one we missed.
    ok_to_write = (seq_num_got == seq_num);
    if (ok_to_write)
      seq_num++;

    command_len = getc();

    // now in data mode
    if (ok_to_write)
      lcdstartcmd();
    for (; command_len; command_len--) {
      // LED will be on 1/4 of the time. Simpler code.
      LED = !(command_len & 3);
      if (ok_to_write)
        lcdsend(getc());
      else
        getc();
    }
    // This can be a display command, as long as this is the last packet.
    // We won't block until we try to sleep.
    lcdendcmd();

    if (header == ETX) {
      sleep_count = getc();
      exponent = getc();
      // We have to retry if we're ignoring this packet.
      if (ok_to_write)
        break;
    }
  }

  LED = 0;

  send_ack();  // Optimization: Turn the radio off before we display.
  SWDTEN = 0;  // We're OK from here, don't reset while drawing the screen!
  lcd_sleep();  // Blocks while the screen updates.
  return 1;
}

void setup_sleeptime(void) {

// The format is two bytes. First byte is a loop count of how many times to
// sleep. The second byte is an exponent for the delay. The exponent has five
// added to it, i.e. the prescaler ranges from 2^5 when exponent is 0 to (max)
// 2^23 when it's 18.

// Things get slightly complicated, because the exponent needs to be split
// across two separate postscalers. The TMR0 postscaler can go up to 7,
// (1:128), while the WDT postscaler goes up to 11. I choose between not using
// the TMR0 scaler, or using it to the max.
  if (exponent > 7) {
    if (exponent > 18)
      exponent = 18;
    exponent -= 7;
    // Disable pull-ups, 128:1 WDT prescaler
    OPTION = 0x8F;
  } else {
    // Disable pull-ups, no WDT prescaler
    OPTION = 0x80;
  }

  // This also disables the WDT, preventing a reset
  WDTCON = exponent << 1;
}

unsigned char backoff_exponent;
// An exponent of 4 gives an initial backoff time of 2.1s.
#define INITIAL_BACKOFF_EXPONENT 4

void main(void) {
  // Initialize backoff if this wasn't a WDT reset
  // Also set button bits before they get mucked with by sleep
  if (!POR) {  // Power-on reset
    button_status = 1 << 7;
    backoff_exponent = 0; // Don't have a long pause on power-on
    seq_num = 0;
  } else if (TO) {  // TO is 0 if WDT reset, 1 otherwise
    button_status = 1 << 6;
    backoff_exponent = 0; // Don't have a long pause with reset button.
  } else {  // WDT reset
    button_status = 1 << 5;
  }
  POR = 1;  // Hardware doesn't set this on reset

  init_all();

#ifdef DEBUG
  // This is a special debug mode for the radish code. The additional features
  // are:
  // 1. It clears the display RAM before every request
  // 2. It sets a flag so that if it resets for any reason during an update,
  //    it will draw whatevers in memory as soon as it resets.
  //
  // This makes it good for testing retry and partial update algorithms.

  if (updating) {  // Draw however much we managed to get
    lcd_disp_fullscrn();
  }
  updating = 0;
#endif
  lcd_sleep();

soft_reset:  // Jump here to simulate a reset, i.e. a bad transmission

  radio_sleep();
  LED = 0;

  // We timed out waiting for a response or data
  // This could also be a power-on reset, but in that case we won't sleep for
  // long at all.
  // The maximum this can sleep for is 4.5 minutes, plus-or-minus the
  // inaccuracy of the 31kHz clock.
  if (backoff_exponent > 11)  // Maximum valid prescaler value
    backoff_exponent = 11;
  WDTCON = backoff_exponent << 1;  // This also turns the WDT off
  backoff_exponent++;
  OPTION = 0x8F;  // Disable pull-ups, 128:1 WDT prescaler

  PORTA;  // Force read this port to clear the wake-on-change latch
  RABIF = 0;  // Clear interrupt flag if set
  SWDTEN = 1;
  SLEEP();
  TO = 1;  // Reset this bit after all sleeps

  // After the initial sleep, reset the backoff time if it's too low. (Happens
  // when we just powered on or the reset button is pressed.)
  if (backoff_exponent < INITIAL_BACKOFF_EXPONENT)
    backoff_exponent = INITIAL_BACKOFF_EXPONENT;

  while(1) {
    cap_voltage = read_analog(0b00001000); // pin AN2 = RA2, left justified
    temp_sensor_on(); // Warm this up now, so it has a chance to stabilize
    // The RC network that provides power to the sensor has an RC constant of
    // 347uS. We wait 2msec ~= 6*RC here, to stabilize the voltage rail and
    // the sensor circuitry.
    pause_msec(2);

    temperature = read_analog(0b10100000); // pin AN8 = RC6, right justified
    temp_sensor_off();

    // Massage the temperature reading to a proper value before sending. The
    // analog reads along the whole voltage scale, so that's 3V. We read the
    // low 8 bits, and bit 9 is represents +-0.75V. Since .75V is room
    // temperature, our range will split right in the middle. We invert the
    // top bit to prevent the split and make the range linear.

    // But first, test to make sure we got some kind of reading at all. A
    // temperature reading of zero indicates that we have no (working) sensor.
    if (ADRESH == 0 && temperature < 128) {
      temperature = 0;
    } else {
      temperature ^= 128;
    }

    // 92 ~= 1.09V. Below that, we can't reliably send a radio message. Since
    // using the radio eats power, and failing to send a message eats even
    // more, just go back to sleep if we're really low.
    // This is needed to prevent the over-the-hump problem where we turn on at
    // .95V but never charge all the way to 1.1V where radio sends become
    // reliable.
    if (cap_voltage >= 92) {
      if (!do_radio_stuff())
        // Yes, gotos are evil, but sometimes they are the only way...
        goto soft_reset;
    } else {
      // Set sane values for sleep_count and exponent. (We can't reuse the old
      // ones - sleep_count gets clobbered in the loop below.) 142 cycles at
      // 31kHz with a total scale of 2^18 (exponent + 5) ~= 1201 seconds.
      sleep_count = 142;
      exponent = 13;
    }

#ifdef DEBUG
    updating = 0;
#endif

    // Successful communication with the wongle - it's implied by the fact
    // that we didn't reset.

    // Paranoia alert: These may already be off, but in case of an aborted
    // transfer...
    LED = 0;
    radio_sleep();

    // Reset the exponential backoff when we suceed
    backoff_exponent = INITIAL_BACKOFF_EXPONENT;
    setup_sleeptime();

    PORTA;  // Force read this port to clear the wake-on-change latch
    RABIF = 0;  // Clear interrupt flag if set
    // Server-controlled sleep time
    // The prescalers were set above
    // sleep_count is a global
    SWDTEN = 1;  // Turn the WDT on so we don't sleep forever
    for (; sleep_count; sleep_count--) {
      // We don't reset RABIF in this loop, so we'll burn through these sleeps
      // if there's a change. And that's exactly what we want.
      SLEEP();
      TO = 1;  // Reset this bit after all sleeps
    }
    SWDTEN = 0;
  }
}
