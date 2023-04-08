#ifndef BOTTOM_ENCODER_DECODER_ZIG
#define BOTTOM_ENCODER_DECODER_ZIG

#ifdef __cplusplus
#define BOTTOM_EXTERN_MODE extern "C"
#else
#define BOTTOM_EXTERN_MODE
#endif

#include <stdint.h>
#define BOTTOM_MAX_EXPANSION_SIZE_PER_BYTE 40

typedef struct Slice
{
    uint8_t *data;
    uintptr_t size;
} BottomSlice;

BOTTOM_EXTERN_MODE void bottom_init_lib();
BOTTOM_EXTERN_MODE BottomSlice bottom_decode_alloc(uint8_t *data, uintptr_t size);
BOTTOM_EXTERN_MODE BottomSlice bottom_decode_buf(uint8_t *data, uintptr_t size, uint8_t *buf, uintptr_t buf_size);
BOTTOM_EXTERN_MODE BottomSlice bottom_encode_alloc(uint8_t *data, uintptr_t size);
BOTTOM_EXTERN_MODE BottomSlice bottom_encode_buf(uint8_t *data, uintptr_t size, uint8_t *buf, uintptr_t buf_size);
BOTTOM_EXTERN_MODE uint8_t bottom_get_error();
BOTTOM_EXTERN_MODE BottomSlice bottom_get_error_string(uint8_t error);
BOTTOM_EXTERN_MODE BottomSlice bottom_get_version();
BOTTOM_EXTERN_MODE void bottom_free_slice(BottomSlice slice);
#endif
