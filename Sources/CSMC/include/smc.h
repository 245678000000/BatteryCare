#pragma once
#include <stdint.h>
int  smc_open(void);
void smc_close(void);
/// Reads up to 32 bytes. type receives a 4-char type code + NUL. Returns 0 on success.
int  smc_read_key(const char *key, uint8_t *out, uint32_t *size, char *type);
/// Writes bytes; size must equal the key's size. Requires root. Returns 0 on success.
int  smc_write_key(const char *key, const uint8_t *data, uint32_t size);
/// Total number of keys (or -1).
int  smc_key_count(void);
/// Key name at index into out (5 bytes). Returns 0 on success.
int  smc_key_at(uint32_t index, char *out);
