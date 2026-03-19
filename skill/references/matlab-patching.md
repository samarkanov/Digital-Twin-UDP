# MATLAB Patching Logic for Portable Binaries

To ensure a standalone C++ binary generated from Simulink is truly portable and container-ready, source-level patching is preferred over binary patching.

## 1. Patch `ert_main.cpp` for Indefinite Execution
Simulink's default main loop is finite. Replace the main function body with an indefinite `while` loop that includes real-time pacing using `usleep`.

```cpp
int_T main(int_T argc, const char *argv[]) {
  (void)(argc); (void)(argv);
  model_obj.initialize();
  while (model_obj.getRTM()->getErrorStatus() == (nullptr)) {
    rt_OneStep(&model_obj);
    usleep(100000); // 0.1s pacing
  }
  model_obj.terminate();
  return 0;
}
```

## 2. Source-Level Path Patching (Crucial)
Generated code often contains hardcoded absolute paths to MATLAB toolbox libraries or uses `coderComputeAbsolutePath`. Patch these in the source code *before* compilation.

**Step A: Replace absolute paths in all source files**
```bash
find build_dir -type f \( -name "*.cpp" -o -name "*.h" \) -exec sed -i 's|/home/.*/\([^"/]*\.so\)|\1|g' {} +
```

**Step B: Bypass `coderComputeAbsolutePath`**
Use `perl` to replace calls that resolve paths at runtime with direct filename assignments:
```bash
perl -0777 -i -pe 's/coderComputeAbsolutePath\(\s*"([^"]+)"\s*,\s*&localAbsPath\[0\]\);/std::strncpy(localAbsPath, "$1", 4096);/gs' build_dir/*.cpp
```

## 3. Gathering Dependencies
Automate recursive gathering using `ldd`, but **exclude** core system libraries to avoid symbol version mismatches (e.g., `GLIBC_PRIVATE`).

**Skip List:** `libc.so`, `libm.so`, `libpthread.so`, `libdl.so`, `librt.so`, `libgcc_s.so`, `ld-linux-x86-64.so.2`.

**Manual Plugin Gathering:**
Some libraries are `dlopen`'d and won't show up in `ldd`. Explicitly copy:
- `libmwudpdevice.so`
- `libmwnetworkcoderconverter.so`
- `libmwnetworksupport.so`
- `libmwbuffer.so`
- `libmwtestcoderconverterarrays.so` (and create symlink `testcoderconverterarrays.so`)

## 4. LD_PRELOAD Interceptor
For any remaining internal absolute `dlopen` calls, use this interceptor to strip paths:
```c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>

typedef void* (*dlopen_t)(const char*, int);

void* dlopen(const char* filename, int flags) {
    dlopen_t original_dlopen = (dlopen_t)dlsym(RTLD_NEXT, "dlopen");
    if (filename && filename[0] == '/') {
        const char* last_slash = strrchr(filename, '/');
        if (last_slash) filename = last_slash + 1;
    }
    return original_dlopen(filename, flags);
}
```
Compile: `gcc -shared -fPIC -o libintercept.so intercept.c -ldl`
Set in Dockerfile: `ENV LD_PRELOAD=/app/libs/libintercept.so`
