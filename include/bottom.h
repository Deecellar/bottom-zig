/**
 * @file bottom.h
 * @brief C API for the Bottom text encoder/decoder
 *
 * This header provides the public C interface for encoding and decoding text
 * using the Bottom encoding scheme. It supports both heap allocation and
 * buffer-based operations.
 *
 * @note Thread safety: All functions are reentrant except bottom_init_lib()
 * @version 1.0
 */

#ifndef BOTTOM_ENCODER_DECODER_ZIG
#define BOTTOM_ENCODER_DECODER_ZIG

#ifdef __cplusplus
#define BOTTOM_EXTERN_MODE extern "C"
#else
#define BOTTOM_EXTERN_MODE
#endif

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 199901L
    #include <stdint.h>
#elif defined(_MSC_VER)
    typedef unsigned char uint8_t;
    typedef size_t uintptr_t;
#else
    #error "C99 or later is required for uint8_t support"
#endif


/** Maximum size expansion factor when encoding a single byte */
#define BOTTOM_MAX_EXPANSION_SIZE_PER_BYTE 40

/**
 * @brief Represents a resizable byte buffer with size information
 */
typedef struct Slice {
    uint8_t *data;     /**< Pointer to the data buffer */
    uintptr_t size;    /**< Size of the data in bytes */
} BottomSlice;

/**
 * @brief Initialize the Bottom library
 * @note Must be called before using any other functions
 */
BOTTOM_EXTERN_MODE void bottom_init_lib();

/**
 * @brief Decode Bottom text with dynamic memory allocation
 * @param data Input buffer containing Bottom-encoded text
 * @param size Length of input in bytes
 * @return BottomSlice containing decoded result (must be freed)
 */
BOTTOM_EXTERN_MODE BottomSlice bottom_decode_alloc(uint8_t *data, uintptr_t size);

/**
 * @brief Decode Bottom text using provided buffer
 * @param data Input buffer containing Bottom-encoded text
 * @param size Length of input in bytes
 * @param buf Output buffer for decoded result
 * @param buf_size Size of output buffer
 * @return BottomSlice containing view into decoded result
 */
BOTTOM_EXTERN_MODE BottomSlice bottom_decode_buf(uint8_t *data, uintptr_t size, uint8_t *buf, uintptr_t buf_size);

/**
 * @brief Encode text to Bottom format with dynamic allocation
 * @param data Input text buffer
 * @param size Length of input in bytes
 * @return BottomSlice containing encoded result (must be freed)
 */
BOTTOM_EXTERN_MODE BottomSlice bottom_encode_alloc(uint8_t *data, uintptr_t size);

/**
 * @brief Encode text to Bottom format using provided buffer
 * @param data Input text buffer
 * @param size Length of input in bytes
 * @param buf Output buffer for encoded result
 * @param buf_size Size of output buffer
 * @return BottomSlice containing view into encoded result
 */
BOTTOM_EXTERN_MODE BottomSlice bottom_encode_buf(uint8_t *data, uintptr_t size, uint8_t *buf, uintptr_t buf_size);

/**
 * @brief Get and clear the current error state
 * @return Error code:
 *         0: No error
 *         1: Memory error
 *         2: Invalid input
 *         3: Windows UTF-8 error
 */
BOTTOM_EXTERN_MODE uint8_t bottom_get_error();

/**
 * @brief Get human-readable error message
 * @param error Error code to get message for
 * @return BottomSlice containing error message string
 */
BOTTOM_EXTERN_MODE BottomSlice bottom_get_error_string(uint8_t error);

/**
 * @brief Get library version string
 * @return BottomSlice containing version information
 */
BOTTOM_EXTERN_MODE BottomSlice bottom_get_version();

/**
 * @brief Free memory allocated by encode/decode functions
 * @param slice BottomSlice to deallocate
 */
BOTTOM_EXTERN_MODE void bottom_free_slice(BottomSlice slice);

#endif /* BOTTOM_ENCODER_DECODER_ZIG */
