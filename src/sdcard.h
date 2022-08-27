/*
 * Copyright lizhirui
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author       Notes
 * 2022-08-27     lizhirui     the first version
 */

#ifndef __SDCARD_H__
#define __SDCARD_H__

    void sdcard_reset();
    void wait_sdcard_ready();
    void sdcard_read(uint32_t dstaddr, uint32_t offset, uint32_t size);
    bool sdcard_is_busy();
    uint32_t sdcard_get_progress();

#endif