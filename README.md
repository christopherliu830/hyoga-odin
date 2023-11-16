Odin vulkan renderer.

- Odin
- Vulkan
- GLFW

## Installing

Clone this repository.

Then, install the submodules with `git submodule update --init --recursive`.

Optionally, you can install `zx` with `npm install -g zx` to run the scripts in `tasks/`.

## Building

```sh
make       # Outputs build/hyoga.exe
make debug # Outputs build/hyogad.exe
```

Alternatively:

```sh
zx tasks/build.mjs
```

## Running

```sh
cd build
./hyoga.exe
```

Alternatively:

```sh
zx tasks/build.mjs
```

## Using zx

Use the command `zx tasks/[task].mjs` to run the included scripts.
It is not required for use.

