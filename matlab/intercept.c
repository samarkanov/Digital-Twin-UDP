#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#include <stdio.h>

/*
 * Intercept dlopen calls to catch absolute paths hardcoded by Simulink Coder
 * and redirect them to the LD_LIBRARY_PATH (/app/libs).
 */
void *dlopen(const char *filename, int flag) {
    static void *(*real_dlopen)(const char *, int) = NULL;
    if (!real_dlopen) {
        real_dlopen = dlsym(RTLD_NEXT, "dlopen");
    }

    if (filename && (strstr(filename, "/toolbox/shared/") || strstr(filename, "/bin/glnxa64/"))) {
        const char *base = strrchr(filename, '/');
        if (base) {
            char new_path[256];
            if (strstr(base + 1, ".so")) {
                snprintf(new_path, sizeof(new_path), "%s", base + 1);
            } else {
                if (strstr(base + 1, "testcoderconverterarrays")) {
                    snprintf(new_path, sizeof(new_path), "libmw%s.so", base + 1);
                } else {
                    snprintf(new_path, sizeof(new_path), "%s", base + 1);
                }
            }
            printf("[Interceptor] Redirecting dlopen: %s -> %s\n", filename, new_path);
            return real_dlopen(new_path, flag);
        }
    }
    
    return real_dlopen(filename, flag);
}

/*
 * Intercept coderComputeAbsolutePath to prevent the MATLAB runtime from failing
 * to find plugins because the host paths don't exist in the Docker container.
 * We force it to return the path in /app/libs/ where we placed the plugins.
 */
void coderComputeAbsolutePath(const char* inPath, char* outPath) {
    if (inPath && outPath) {
        const char *base = strrchr(inPath, '/');
        if (!base) {
            base = inPath;
        } else {
            base++; // Skip the slash
        }
        
        // Ensure it ends with .so
        if (strstr(base, ".so")) {
            snprintf(outPath, 4096, "/app/libs/%s", base);
        } else {
            snprintf(outPath, 4096, "/app/libs/%s.so", base);
        }
        printf("[Interceptor] coderComputeAbsolutePath: %s -> %s\n", inPath, outPath);
    }
}
