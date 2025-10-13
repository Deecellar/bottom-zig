/**
 * @file bottom.h
 * @brief C API for the Bottom text encoder/decoder
 *
 * This header provides the public C interface for encoding and decoding text
 * using the Bottom encoding scheme (emoji-based text encoding).
 *
 * ## Quick Start
 * 1. Call bottom_init_lib() before any other functions
 * 2. Use bottom_encode_alloc() / bottom_decode_alloc() for automatic memory management
 * 3. Check errors with bottom_get_error() after operations
 * 4. Free allocated results with bottom_free_slice()
 *
 * ## Error Handling
 * Error codes:
 * - 0: No error
 * - 1: Memory allocation failed or buffer too small
 * - 2: Invalid Bottom encoding in input
 * - 3: Windows console UTF-8 not supported (requires Windows Terminal)
 *
 * ## Buffer Sizing
 * - Encoding: output buffer must be at least input_len * 48 bytes
 * - Decoding: output buffer must be at least input_len bytes
 *
 * @warning This API is NOT thread-safe due to global error state
 * @version 0.1.0
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


/** Maximum bytes a single input byte can expand to when encoded (worst-case) */
#define BOTTOM_MAX_EXPANSION_SIZE_PER_BYTE 40

/**
 * @brief Represents a byte buffer with explicit length
 *
 * Used for both input and output in Bottom encoding/decoding operations.
 * For *_alloc functions, caller owns memory and must call bottom_free_slice().
 * For *_buf functions, data points into caller-provided buffer.
 */
typedef struct Slice {
    uint8_t *data;     /**< Pointer to buffer (NULL indicates error) */
    uintptr_t size;    /**< Length of data in bytes (0 indicates error) */
} BottomSlice;

/**
 * @brief Initialize the Bottom library
 *
 * On Windows, attempts to set console to UTF-8 mode (CP65001).
 * On other platforms, this is a no-op.
 *
 * @note Call this before any other Bottom functions
 * @warning Sets global error code 3 if Windows UTF-8 setup fails
 */
BOTTOM_EXTERN_MODE void bottom_init_lib();

/**
 * @brief Decode Bottom-encoded text with automatic memory allocation
 *
 * @param data Pointer to Bottom-encoded text
 * @param size Length of input in bytes
 * @return BottomSlice with decoded data. Caller must free with bottom_free_slice().
 *         Returns {NULL, 0} on error - check with bottom_get_error().
 */
BOTTOM_EXTERN_MODE BottomSlice bottom_decode_alloc(uint8_t *data, uintptr_t size);

/**
 * @brief Decode Bottom-encoded text using caller-provided buffer
 *
 * @param data Pointer to Bottom-encoded text
 * @param size Length of input in bytes
 * @param buf Output buffer (must be >= size bytes for safety)
 * @param buf_size Size of output buffer
 * @return BottomSlice pointing into buf with actual decoded length.
 *         Returns {NULL, 0} on error - check with bottom_get_error().
 * @note Does not allocate memory. buf must be large enough.
 */
BOTTOM_EXTERN_MODE BottomSlice bottom_decode_buf(uint8_t *data, uintptr_t size, uint8_t *buf, uintptr_t buf_size);

/**
 * @brief Encode text to Bottom format with automatic memory allocation
 *
 * @param data Pointer to input text
 * @param size Length of input in bytes
 * @return BottomSlice with encoded data. Caller must free with bottom_free_slice().
 *         Returns {NULL, 0} on error - check with bottom_get_error().
 */
BOTTOM_EXTERN_MODE BottomSlice bottom_encode_alloc(uint8_t *data, uintptr_t size);

/**
 * @brief Encode text to Bottom format using caller-provided buffer
 *
 * @param data Pointer to input text
 * @param size Length of input in bytes
 * @param buf Output buffer (must be >= size * 48 bytes)
 * @param buf_size Size of output buffer
 * @return BottomSlice pointing into buf with actual encoded length.
 *         Returns {NULL, 0} on error - check with bottom_get_error().
 * @note Does not allocate memory. buf must be large enough (size * 48 worst-case).
 */
BOTTOM_EXTERN_MODE BottomSlice bottom_encode_buf(uint8_t *data, uintptr_t size, uint8_t *buf, uintptr_t buf_size);

/**
 * @brief Get and automatically reset the current error state
 *
 * @return Error code:
 *         - 0: No error
 *         - 1: Memory allocation failed or buffer too small
 *         - 2: Invalid Bottom encoding
 *         - 3: Windows console UTF-8 not supported
 * @note Calling this function resets the internal error state to 0
 */
BOTTOM_EXTERN_MODE uint8_t bottom_get_error();

/**
 * @brief Get human-readable error message for an error code
 *
 * @param error Error code from bottom_get_error()
 * @return BottomSlice with static error string. DO NOT free this slice.
 */
BOTTOM_EXTERN_MODE BottomSlice bottom_get_error_string(uint8_t error);

/**
 * @brief Get library version string
 *
 * @return BottomSlice with static version string. DO NOT free this slice.
 */
BOTTOM_EXTERN_MODE BottomSlice bottom_get_version();

/**
 * @brief Free memory allocated by *_alloc functions
 *
 * @param slice BottomSlice returned by bottom_encode_alloc() or bottom_decode_alloc()
 * @warning Only call this for slices from *_alloc functions, NOT *_buf functions
 * @warning Do NOT free slices from bottom_get_version() or bottom_get_error_string()
 */
BOTTOM_EXTERN_MODE void bottom_free_slice(BottomSlice slice);

#endif /* BOTTOM_ENCODER_DECODER_ZIG */
