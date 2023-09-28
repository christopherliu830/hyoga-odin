UNAME := $(shell uname)

PROJECT_NAME = hyoga
OUT_DIR = build
RELEXE = ${OUT_DIR}/${PROJECT_NAME}.exe
DBGEXE = ${OUT_DIR}/${PROJECT_NAME}d.exe

VULKAN_DIR = ${VULKAN_SDK}

ODIN_SOURCE_DIR = src

SHADER_COMPILER = glslc
SHADER_FLAGS = -c

ODIN_COMPILER = odin
ODIN_FLAGS = -collection:externals=externals            \
			 -collection:memory=src/memory              \
			 -collection:graphics=src/graphics          \
			 -collection:pkgs=pkgs

RELODIN_FLAGS = -out=${RELEXE} ${ODIN_FLAGS}
DBGODIN_FLAGS = -debug -out=${DBGEXE} ${ODIN_FLAGS}
ODIN_SOURCES = $(wildcard ${ODIN_SOURCE_DIR}/*.odin) $(wildcard **/*.odin)

# Default target
all: release install

# DEBUG
debug: $(DBGEXE) install

$(DBGEXE): FORCE
	$(ODIN_COMPILER) build $(ODIN_SOURCE_DIR) $(DBGODIN_FLAGS) 

# Release
release: $(RELEXE) install

$(RELEXE): FORCE
	$(ODIN_COMPILER) build $(ODIN_SOURCE_DIR) $(RELODIN_FLAGS) 

# Prep
install: shaders

# SHADERS -----------------------------------------------------------
SHADER_SOURCE_DIR = assets/shaders
SHADER_BUILD_DIR = build/assets/shaders

# List of shader source files and corresponding build targets
SHADER_SOURCES = $(wildcard $(SHADER_SOURCE_DIR)/*.vert $(SHADER_SOURCE_DIR)/*.frag)
SHADER_OBJECTS = $(patsubst \
	$(SHADER_SOURCE_DIR)/%.vert, \
	$(SHADER_BUILD_DIR)/%.vert.spv, \
	$(patsubst $(SHADER_SOURCE_DIR)/%.frag, \
	$(SHADER_BUILD_DIR)/%.frag.spv, \
	$(SHADER_SOURCES)) \
)

shaders: $(SHADER_OBJECTS)

$(SHADER_BUILD_DIR)/%.spv: $(SHADER_SOURCE_DIR)/%
	@mkdir -p $(@D)
	$(SHADER_COMPILER) $(SHADER_FLAGS) $< -o $@

FORCE: ;

