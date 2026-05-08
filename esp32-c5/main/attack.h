#pragma once

#include <stdint.h>
#include <stdbool.h>

void attack_init(void);

/* Returns true if attack started. */
bool attack_start(uint32_t duration_seconds);
void attack_stop(void);

bool attack_is_running(void);
void attack_print_status(void);
