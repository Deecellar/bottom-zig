#include <bottom/bottom.h>
#include <stdio.h>
int main()
{
    // We init the lib so in windows or other platforms
    // With special consideations for terminal can start
    // on Utf-8 (for now windows only)
    bottom_init_lib();
    uint8_t err = 0;

    if (err = bottom_get_error() == 3)
    {
        printf("Error: %d\n", err);
        printf("%s\n", bottom_get_error_string(err));
    }
    char *str = "Hello, world!";
    BottomSlice slice, slice2, version;
    slice = bottom_encode_alloc(str, strlen(str));
    slice2 = bottom_decode_alloc(slice.data, slice.size);
    printf("%s\n", str);
    printf("%.*s\n", slice.size, slice.data);
    printf("%.*s\n", slice2.size, slice2.data);
    // Version does not need to be freed.
    version = bottom_get_version();
    printf("%.*s\n", version.size, version.data);

    bottom_free_slice(slice);
    bottom_free_slice(slice2);

    // error handling
    err = 0;

    slice2 = bottom_decode_alloc(str, strlen(str));
    // This will cause an error.
    if (slice2.size == 0)
    {
        err = bottom_get_error(); // This will return the current error which is invalid input
        printf("Error: %d\n", err);
        printf("%s\n", bottom_get_error_string(err));
    }

    slice = bottom_decode_alloc(str, strlen(str));
    if (slice.data == NULL)
    {
        err = bottom_get_error(); // This will return the current error. which will be invalid input.
        printf("Error: %d\n", err);
        printf("%s\n", bottom_get_error_string(err));
    }
    // if we do it again it will return no error.
    err = bottom_get_error();
    printf("Error: %d\n", err);
    printf("%s\n", bottom_get_error_string(err));

    return 0;
}