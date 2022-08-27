/*
 * Copyright lizhirui
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author       Notes
 * 2022-08-27     lizhirui     the first version
 */

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

typedef struct sdc_reg
{
	volatile uint32_t ctrl;
	volatile uint32_t stat;
	volatile uint32_t dstaddr;
	volatile uint32_t startsector;
	volatile uint32_t sectornum;
	volatile uint32_t progress;
	volatile uint32_t reset;
}sdc_reg_t;

//SD Controller Base Address
static volatile sdc_reg_t *sdc = (volatile sdc_reg_t *)0x42000000;

//this function is to get current system time (unit microsecond) for timeout check
static uint64_t get_ms_time()
{
	return 0;
}

void sdcard_reset()
{
	sdc->reset = 0x01;
}

void wait_sdcard_ready()
{
	uint64_t cur_time = get_ms_time();
	uint32_t last_progress = sdc->progress;

	while((sdc->stat & 0x01) == 1)
	{
		if(sdc->progress != last_progress)
		{
			last_progress = sdc->progress;
			cur_time = get_ms_time();
		}
		else if((get_ms_time() - cur_time) > 500)
		{
			printf("sdcard is timeout, retry!\n");
			sdcard_reset();
			while((sdc->stat & 0x01) == 1);
			cur_time = get_ms_time();
			last_progress = sdc->progress;
			sdc->ctrl = 1;
		}
	}
}

void sdcard_read(uint32_t dstaddr, uint32_t offset, uint32_t size)
{
    wait_sdcard_ready();
	while((sdc->stat & 0x01) == 1);
    sdc->dstaddr = dstaddr;
    sdc->startsector = offset / 512;
    sdc->sectornum = size / 512;
    sdc->ctrl = 1;
}

bool sdcard_is_busy()
{
    return sdc->stat & 0x01;
}

uint32_t sdcard_get_progress()
{
    return sdc->progress;
}
