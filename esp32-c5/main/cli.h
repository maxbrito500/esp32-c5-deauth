#pragma once

#include <stdint.h>
#include <stddef.h>

void cli_init(void);

/* Bytes from any transport — assembles lines, runs commands. */
void cli_feed(const char *bytes, size_t len);
