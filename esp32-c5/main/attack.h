#pragma once

#include <stdint.h>
#include <stdbool.h>

void attack_init(void);

/* Targeted attack — uses the sel list; duration_seconds=0 runs until stop. */
bool attack_start(uint32_t duration_seconds);

/* Nuke — deauths every AP in the scan list with mixed mode. */
bool attack_nuke_start(uint32_t duration_seconds);

void attack_stop(void);

bool attack_is_running(void);
void attack_print_status(void);
