# Updating the vendored ArduinoCore-API

`ArduinoCore-API/` is a git submodule tracking the upstream repo.
`cores/tangnano20k/api/` is **not** the submodule itself — arduino-cli
recursively compiles every `.c`/`.cpp`/`.S` file under the core directory,
and the submodule's root also carries a Catch2 `test/` tree that isn't
meant to be built into a sketch. `tools/vendor_arduino_api.sh` copies just
the needed subset (all headers, plus only the `.cpp` files this core
actually links: `Common.cpp`, `Print.cpp`, `Stream.cpp`, `String.cpp` -
the last needs `malloc`/`free`/`realloc`, see
`cores/tangnano20k/tangnano20k_malloc.c`). `IPAddress.cpp`, `CanMsg*.cpp`,
and `PluggableUSB.cpp` are still left out - they'd need actual networking/
USB support this bare-metal core doesn't provide.

After updating the submodule:

```sh
cd ArduinoCore-API && git pull origin main && cd ..
git add ArduinoCore-API
./tools/vendor_arduino_api.sh
git add cores/tangnano20k/api
```
