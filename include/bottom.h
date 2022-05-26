#ifndef BOTTOM_ENCODER_DECODER_ZIG
#define BOTTOM_ENCODER_DECODER_ZIG

#include <stdint.h>
#define BOTTOM_MAX_EXPANSION_SIZE_PER_BYTE 40

typedef struct Slice {
    uint8_t* data;
    uintptr_t size;
} BottomSlice ;

BottomSlice bottom_decode_alloc(uint8_t* data, uintptr_t size);
BottomSlice bottom_decode_buf(uint8_t* data, uintptr_t size, uint8_t* buf, uintptr_t buf_size);
BottomSlice bottom_encode_alloc(uint8_t* data, uintptr_t size);
BottomSlice bottom_encode_buf(uint8_t* data, uintptr_t size, uint8_t* buf, uintptr_t buf_size);
uint8_t bottom_get_error();
BottomSlice bottom_get_error_string(uint8_t error);
BottomSlice bottom_get_version();
#endif
