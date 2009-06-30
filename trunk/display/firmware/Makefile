# Copyright 2009 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

CHIP=16f690
PICL=picl -q --asmlist --summary=file --chip=$(CHIP) --runtime=-clear
PK2CMD=pk2cmd
PROGRAM=$(PK2CMD) -1 -ppic$(CHIP) -m

%.obj : %.c ; $(PICL) -c $<

%.hex : %.obj
	$(PICL) -o$@ $^
	chmod a+r $@

program_% : %.hex ; ${PROGRAM} -f$<

default: all

all: main.hex flash_xbee.hex blink_test.hex

main.hex: main.obj init.obj pause.obj lcd.obj xbee.obj

main.obj: main.c revision.h

revision.h: main.c stamp_revision.py
	./stamp_revision.py < $< > $@

flash_xbee.hex: flash_xbee.obj init.obj

blink_test.hex: blink_test.obj init.obj pause.obj

debug.hex: debug.obj init.obj pause.obj lcd.obj xbee.obj

debug.obj: main.c revision.h
	$(PICL) -DDEBUG -c $< -o$@

clean:
	rm -f *.obj *.hex *.cof *.hxl *.lst *.sdb *.sym *.rlf *.p1 *~ revision.h

program: program_main
