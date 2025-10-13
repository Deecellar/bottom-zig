/*
 * Bottom Encoding C API Example
 *
 * This tutorial demonstrates:
 * 1. Library initialization (required on Windows for UTF-8 console support)
 * 2. Basic encoding/decoding with automatic memory allocation
 * 3. Error handling patterns
 * 4. Memory management (when to free, when not to)
 */

#include <bottom/bottom.h>
#include <stdio.h>
#include <string.h>

int main()
{
    // Step 1: Initialize the library
    // On Windows, this sets the console to UTF-8 mode. On other platforms, it's a no-op.
    // IMPORTANT: Always call this before any other Bottom API functions.
    bottom_init_lib();
    uint8_t err = 0;

    // Check if initialization failed (Windows-specific error)
    if ((err = bottom_get_error()) == 3)
    {
        printf("Error: %d\n", err);
        printf("%s\n", bottom_get_error_string(err));
        // Note: On Windows without UTF-8 support, you'll need Windows Terminal
    }

    // Step 2: Basic encoding and decoding
    char *str = "Hello, world!";
    BottomSlice slice, slice2, version;

    // Encode text to Bottom format (allocates memory internally)
    slice = bottom_encode_alloc((uint8_t*)str, strlen(str));

    // Decode Bottom back to text (allocates memory internally)
    slice2 = bottom_decode_alloc((uint8_t*)slice.data, slice.size);

    // Print results
    printf("Original:  %s\n", str);
    printf("Encoded:   %.*s\n", (int)slice.size, slice.data);
    printf("Decoded:   %.*s\n", (int)slice2.size, slice2.data);

    // Step 3: Query library version
    // Version string is static - DO NOT free this slice
    version = bottom_get_version();
    printf("Version:   %.*s\n", (int)version.size, version.data);

    // Step 4: Free allocated memory
    // IMPORTANT: Only free slices returned by *_alloc functions
    bottom_free_slice(slice);
    bottom_free_slice(slice2);

    // Step 5: Error handling demonstration
    err = 0;

    // Try to decode plain text (not valid Bottom encoding) - this will fail
    slice2 = bottom_decode_alloc((uint8_t*)str, strlen(str));

    // Two ways to detect errors:
    // 1. Check for zero size in returned slice
    if (slice2.size == 0)
    {
        err = bottom_get_error();  // Error code 2 = invalid Bottom encoding
        printf("\nExpected error (invalid input):\n");
        printf("Error code: %d\n", err);
        printf("Error message: %s\n", bottom_get_error_string(err));
    }

    // 2. Check for NULL pointer in returned slice (same error, different check)
    slice = bottom_decode_alloc((uint8_t*)str, strlen(str));
    if (slice.data == NULL)
    {
        err = bottom_get_error();  // Same error code 2
        printf("\nSame error detected via NULL check:\n");
        printf("Error code: %d\n", err);
        printf("Error message: %s\n", bottom_get_error_string(err));
    }

    // Important: bottom_get_error() automatically resets the error state
    // Calling it again returns 0 (no error)
    err = bottom_get_error();
    printf("\nError state after reset:\n");
    printf("Error code: %d\n", err);
    printf("Error message: %s\n", bottom_get_error_string(err));

    return 0;
}