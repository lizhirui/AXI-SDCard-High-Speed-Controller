# AXI SD Card High Speed Controller

High-speed SD card controller based on AXI interface

## Acknowledge

A portion of the code from this project's `sdcmd ctrl.sv` and `sd reader.sv` files is referenced form the `https://github.com/WangXuan95/FPGA-SDcard-Reader` project and`SD Specifications Part 1 Physical Layer Speicifcation Version 3.00 April 16, 2009`

## Features

The SD card controller has the following features.

1. operates in 50MHz SDIO 4-wire high-speed mode
2. operates in the SD card multi-block transfer model
3. transfer rates up to 23MB/s
4. Active DMA on AXI4 interface (supports 256 bursts)
5. AXILite configuration interface
6. Supports up to 4GiB of data in one transfer
7. Start sector up to 0xFFFFFFFF, i.e. access to any data in the entire range of the first 1TiB of the SD card
8. Only read-only data be supported

## Design Architecture

![avatar](docs/sdc.png)

## File Structure

The purpose of each file in the rtl directory is listed below: 

|File name| Description                                                  |
|---|---|
|sdcmd_ctrl.sv|SDIO PHY layer, which implements the basic SDIO sequential logic|
|sd_reader.sv|SDIO MAC layer, which implements the basic command set and sector read control for SD cards|
|sd_controller_regfile.sv|AXILite controller register configuration interface and register implementation|
|sd_controller_ping_pong_buffer.sv|Ping/Pong Buffer|
|sd_controller_axi_writer.sv|AXI4 DMA which support write only 256 burst|
|sd_controller.sv|SD card controller top level layer|
|sd_controller_wrapper.v|Verilog card controller packaging|

## Implementation principle

The controller starts by outputting a 400KHz clock, a 25MHz clock after completing the basic SD card configuration process, and a 50MHz clock after switching to high speed mode.

To achieve such high-speed transfers, the controller uses Xilinx FPGA primes and constraints, with the primes partially implemented in a Verilog wrapper layer:

![avatar](docs/sdc_port.png)

Highlight:
* BUFG converts the SD Reader's clock into a specialized FPGA clock network to optimize FF timing.
* ODDR is used to align the clock to the command output, among them the top ODDR is used to output the clock, and since D1 is connected to 0 and D2 to 1, ODDR will output a clock that is 180 degrees out of phase with the original clock, and since SDCMDOUT is changed at SDCLK, after the output clock is inverted, the Setup/Hold Timing of SDCMD relative to the output clock can be greatly improved to provide enough margin for the signal to be routed on the PCB.
* The SDCMDOE is tapped twice to align with the output SDCMDOUT signal and ensure that the tri-state gate is switched at the correct timing.
* SDCMDIN begins with tapped once on the FF of the IOB (where the signal now belongs to the sdclk_bufg clock domain), ensuring that the signal retains appropriate Timing margin after PCB alignment. Next, the signal from IOB FF is tapped again on LUT FF. The clock used at this point is aclk, the controller clock (100MHz in this case), to achieve a cross-clock domain. This approach is taken across the clock domain because sdclk_bufg is itself the generated clock for aclk. As a result, the synthesizer STA is able to accurately calculate Setup/Hold Time, which ensures that sub-stable problems, which typically arise across the clock domain, do not occur in this scenario.
* The SDDAT is a similar situation, first one tapped on IOB FF via sdclk_bufg and then one tapped with aclk, which is fed into the SDIO Reader.

## Hardware deployment

The top-level module is sd_controller_wrapper, where the individual ports are described as follows:

|Port|Direction|Description|
|---|---|---|
|aclk|I|Controller clock (also AXI4 and AXILite clocks), must be 100MHz|
|aresetn|I|Controller reset signal (also as AXI4 and AXILite bus reset signal), active low|
|axilite_*|I/O|AXILite Slave configuration interface signal (configuration space size 4KB, both address data width 32bit)|
|axi_*|I/O|AXI4 Master DMA Write-Only interface signal (both address data width 32 bit)|
|sdclk|O|SD card clock line|
|sdcmd|I/O|SD card command line|
|sddat|I|SD card data line|
|card_type|O|SD card type signal|
|card_stat|O|SD card controller current status|
|interrupt|O|Interrupt signal, active high|
|test_*|O|For testing purposes only|

In order for the synthesizer to correctly calculate the STA across the clock domain, the following generation clock constraints need to be added (controller clock 100MHz, SDIO clock max 50MHz, set at 2 divisions):
```
create_generated_clock -name sdclk -source [get_pins top_design_i/clk_wiz_main/clk_out3] -divide_by 2 [get_pins top_design_i/sd_controller_wrapper_0/inst/sd_controller_inst/sd_reader_inst/sdcmd_ctrl_inst/sdclk_reg/Q]
```

where note that `top_design_i/clk_wiz_main/clk_out3` need to be changed to the correct controller clock.

Currently tested on `KC705` platform with FPGA `XC7K325T-2FFG900`, if you need to use other FPGA, please take care to replace the original language in `sd_controller_wrapper.v`.

The module can be used directly by Verilog or SystemVerilog or can be added directly to Vivado's Block Design for use.

## Software deployment

An example software driver is available in the src directory which provides the following functions:

|Function|Description|
|---|---|
|sdcard_reset|Reset SD card controller|
|wait_sdcard_ready|Waiting for the SD card controller to be ready (timeout detection implemented, auto resent the command if timeout)|
|sdcard_read|Read SD card data, this function will wait for the SD card controller to be ready before initiating the command (timeout detection implemented, auto resent the command if timeout)|
|sdcard_is_busy|Returns TRUE to indicate that the SD card controller is busy|
|sdcard_get_progress|Get SD card controller progress|

For the timeout function to work, the user must populate the `get_ms_time` function in `sdcard.c`, which serves to range the system time in milliseconds.

Note that `sdc` need to be adjusted to point to the right SD card controller base address.

## Register Map

|Offset|Name|Properties| Description                                              |
|---|---|---|---|
|0x00|CTRL|RW|Control Registers|
|0x04|STAT|RO（RW for INT）|Status Register|
|0x08|DSTADDR|RW|Target address|
|0x0C|STARTSECTOR|RW|Starting sector|
|0x10|SECTORNUM|RW|Number of sectors (in 512 bytes, must be an even number)|
|0x14|PROGRESS|RO|Current progress (number of bytes)|
|0x18|RESET|RW|Reset Register|

RW - Read Write RO - Read Only

Control register:

|bits|Name|Description|
|---|---|---|
|31:2|Reserved|Always 0|
|1|INT_EN|Interrupt (1 for enable, 0 for disable)|
|0|START|Start transmission (1 to start, reads constant 0)|

Status register:

| bits | Name      | Description                                                 |
|---|---|---|
|31:9|Reserved|Always 0|
|8:5|Card Stat|SD card controller state|
|4:3|Card Type|SD Card Type|
|2|INT|Interrupt hang (write 1 to this bit to clear the interrupt)|
|1|DMA Error|DMA write Memory send error|
|0|BUSY|In transit (1 means in transit, 0 means idle)|

The values and meanings of Card Stat are as follows.

|Value|Meaning|
|---|---|
|0000|CMD0 (GO_IDLE_STATE) command being sent, controller remains idle|
|0001|CMD8 (SEND_IF_COND) command being sent and waiting for response|
|0010|CMD55 (APP_CMD) command being sent and waiting for response|
|0011|ACMD41 (SD_SEND_OP_COND) command being sent and waiting for response|
|0100|CMD2 (ALL_SEND_CID) command being sent and waiting for response|
|0101|CMD3 (SEND_RELATIVE_ADDR) command being sent and waiting for response|
|0110|CMD7 (SELECT_CARD) command being sent and waiting for response|
|0111|CMD55 (APP_CMD) command being sent and waiting for response|
|1000|ACMD6 (SET_BUS_WIDTH) command being sent and waiting for response|
|1001|CMD6 (SWITCH_FUNC) command being sent and waiting for response|
|1010|CMD16 (SET_BLOCKLEN) command being sent and waiting for response|
|1011|Preparing to send the CMD18 (READ_MULTIPLE_BLOCK) command|
|1100|Waiting for response to CMD18 (READ_MULTIPLE_BLOCK) command|
|1101|Data being received from SD card|
|1110|CMD12 (STOP_TRANSMISSION) command being sent and waiting for response|
|1111|Waiting for the data reception state to reach the end of read state|

The values and meanings of Card Type are as follows:

|Value|Meaning|
|---|---|
|0000|Unknown type|
|0001|SD 1.0|
|0010|SD 2.0|
|0011|SDHC/XC 2.0|
|0100|Maybe SD 1.0 card (only as intermediate, not as final state)|
|0101~1111|Reserved|

Target address register:

|bit|Name| Description    |
|---|---|---|
|31:0|DSTADDR|Target address|

Starting sector register:

| bit  | Name        | Description                                                  |
|---|---|---|
|31:0|STARTSECTOR|Start sector (one sector is 512 bytes, do not exceed the SD card capacity range)|

Sector count register:

| bit   | Name      | Description                                                  |
|---|---|---|
|31:23| Reserved  |Always 0|
|22:1|SECTORNUM|Number of sectors (because 1KB of data is transferred at a time, the number of sectors must be even and cannot be zero, which is why the AXI burst is 256, 256 * 32bit = 1KiB)|
|0|Reserved|Always 0|

Current progress register:

| bit  | Name     | Description                                                 |
|---|---|---|
|31:0|PROGRESS|Current amount of completed data transferred by DMA (bytes)|

Reset register:

| bit  | Name     | Description                                          |
|---|---|---|
|31:1|Reserved|Always 0|
|0|RESET|Write 1 to reset SD card controller, read constant 0|

## Speed Test

The module's accuracy is very high because it has been tested with a huge number of data transfers utilizing two registers (the transfer cycle count register and the transfer byte count register) and translated from clock cycles using ILA sampling. The following graph displays the measured transfer rate curve (from SD card to DDR3). The SD card used is a TECLAST UHS-1 64GB card, and the horizontal and vertical coordinates represent the block size and transfer rate, respectively:

![avatar](docs/speed.png)

It can be seen that the transfer rate peaks at about 23MB/s when the block size is 512KB. This peak value is close to the theoretical upper limit of 25MB/s (50MHz * 4bit = 25MiB/Sec) under hardware power (3.3V) and clock conditions (50MHz SDIO 4-wire).

The specific data table is as follows:

|Data size (Byte)|Transmission speed（MiB/Sec）|
|---|---|
|512B|0.95|
|1K|1.83|
|2K|3.39|
|4K|5.92|
|8K|9.42|
|16K|13.38|
|32K|16.94|
|64K|19.54|
|128K|21.16|
|256K|22.08|
|512K|22.81|