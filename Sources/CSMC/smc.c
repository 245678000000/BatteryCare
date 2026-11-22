#include "smc.h"
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <string.h>

typedef struct { char major, minor, build, reserved; uint16_t release; } SMCVers;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimit;
typedef struct { uint32_t dataSize; uint32_t dataType; char dataAttributes; } SMCKeyInfo;
typedef struct {
    uint32_t key; SMCVers vers; SMCPLimit pLimitData; SMCKeyInfo keyInfo;
    char result; char status; char data8; uint32_t data32; uint8_t bytes[32];
} SMCParam;

enum { kSMCUserClient = 2, kSMCReadKey = 5, kSMCWriteKey = 6, kSMCGetKeyInfo = 9 };

static io_connect_t conn = 0;

static uint32_t k2u(const char *k) {
    return ((uint32_t)(uint8_t)k[0] << 24) | ((uint32_t)(uint8_t)k[1] << 16) |
           ((uint32_t)(uint8_t)k[2] << 8) | (uint32_t)(uint8_t)k[3];
}

int smc_open(void) {
    if (conn) return 0;
    io_service_t s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!s) return -1;
    kern_return_t r = IOServiceOpen(s, mach_task_self(), 0, &conn);
    IOObjectRelease(s);
    if (r != KERN_SUCCESS) { conn = 0; return -2; }
    return 0;
}

void smc_close(void) { if (conn) { IOServiceClose(conn); conn = 0; } }

static int call(SMCParam *in, SMCParam *out) {
    size_t sz = sizeof(SMCParam);
    kern_return_t r = IOConnectCallStructMethod(conn, kSMCUserClient, in, sizeof(SMCParam), out, &sz);
    return (r == KERN_SUCCESS && out->result == 0) ? 0 : -1;
}

static int key_info(uint32_t key, SMCKeyInfo *info) {
    SMCParam in, out; memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = key; in.data8 = kSMCGetKeyInfo;
    if (call(&in, &out)) return -1;
    *info = out.keyInfo;
    return 0;
}

int smc_read_key(const char *key, uint8_t *outBytes, uint32_t *size, char *type) {
    if (smc_open()) return -1;
    uint32_t k = k2u(key); SMCKeyInfo info;
    if (key_info(k, &info)) return -2;
    SMCParam in, out; memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = k; in.keyInfo.dataSize = info.dataSize; in.data8 = kSMCReadKey;
    if (call(&in, &out)) return -3;
    uint32_t n = info.dataSize > 32 ? 32 : info.dataSize;
    memcpy(outBytes, out.bytes, n);
    *size = n;
    if (type) {
        type[0] = (char)(info.dataType >> 24); type[1] = (char)(info.dataType >> 16);
        type[2] = (char)(info.dataType >> 8);  type[3] = (char)info.dataType; type[4] = 0;
    }
    return 0;
}

int smc_write_key(const char *key, const uint8_t *data, uint32_t size) {
    if (smc_open()) return -1;
    uint32_t k = k2u(key); SMCKeyInfo info;
    if (key_info(k, &info)) return -2;
    if (size != info.dataSize || size > 32) return -4;
    SMCParam in, out; memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = k; in.data8 = kSMCWriteKey; in.keyInfo.dataSize = info.dataSize;
    memcpy(in.bytes, data, size);
    return call(&in, &out) ? -3 : 0;
}

int smc_key_count(void) {
    uint8_t b[32]; uint32_t n = 0; char t[5];
    if (smc_read_key("#KEY", b, &n, t) || n < 4) return -1;
    return (int)(((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | b[3]);
}

int smc_key_at(uint32_t index, char *out) {
    if (smc_open()) return -1;
    SMCParam in, o; memset(&in, 0, sizeof in); memset(&o, 0, sizeof o);
    in.data8 = 8; in.data32 = index;
    if (call(&in, &o)) return -2;
    out[0] = (char)(o.key >> 24); out[1] = (char)(o.key >> 16); out[2] = (char)(o.key >> 8); out[3] = (char)o.key; out[4] = 0;
    return 0;
}
