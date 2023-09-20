UNAME := $(shell uname)

PROJECT_NAME = hyoga
OUT_DIR = build
RELEXE = ${OUT_DIR}/${PROJECT_NAME}.exe
DBGEXE = ${OUT_DIR}/${PROJECT_NAME}.debug.exe

VULKAN_DIR = ${VULKAN_SDK}

ODIN_SOURCE_DIR = src

SHADER_COMPILER = glslc
SHADER_FLAGS = -c

ODIN_COMPILER = odin
RELODIN_FLAGS = -out=${RELEXE} -collection:externals=./externals
DBGODIN_FLAGS = -debug -out=${DBGEXE} -vet -collection:externals=./externals

ODIN_SOURCES = $(wildcard ${ODIN_SOURCE_DIR}/*.odin) $(wildcard ${ODIN_SOURCE_DIR}/*/*.odin)

# Default target
all: release install

# DEBUG
debug: $(DBGEXE) install

$(DBGEXE): $(ODIN_SOURCES)
	$(ODIN_COMPILER) build $(ODIN_SOURCE_DIR) $(DBGODIN_FLAGS) 

# Release
release: $(RELEXE) install

$(RELEXE): $(ODIN_SOURCES)
	$(ODIN_COMPILER) build $(ODIN_SOURCE_DIR) $(RELODIN_FLAGS) 

# Prep
install: vma shaders

# VMA ----------------------------------------------------------------

VMA_SOURCE_DIR = pkgs/VulkanMemoryAllocator
VMA_BUILD_DIR = externals/vma

vma: $(VMA_BUILD_DIR)

# $(VMA_BUILD_DIR): $(VMA_SOURCE_DIR)
# 	cmake -S $(VMA_SOURCE_DIR) -B $(VMA_SOURCE_DIR)/build -DVMA_STATIC_VULKAN_FUNCTIONS=OFF
# 	msbuild.exe $(VMA_SOURCE_DIR)/build/VulkanMemoryAllocator.sln -p:Configuration=Release
# 	msbuild.exe $(VMA_SOURCE_DIR)/build/VulkanMemoryAllocator.sln
# 	cmake --install $(VMA_SOURCE_DIR)/build --prefix $(VMA_SOURCE_DIR)/build/install
# 	mkdir -p $(VMA_BUILD_DIR)
# 	mv $(VMA_SOURCE_DIR)/build/src/Release/* $(VMA_BUILD_DIR)
# 	mv $(VMA_SOURCE_DIR)/build/src/Debug/* $(VMA_BUILD_DIR)

$(VMA_BUILD_DIR): $(VMA_SOURCE_DIR)
	cmake -S $(VMA_SOURCE_DIR) -B $(VMA_SOURCE_DIR)/build -DVMA_STATIC_VULKAN_FUNCTIONS=OFF
	cmake --build $(VMA_SOURCE_DIR)/build
	cmake --install $(VMA_SOURCE_DIR)/build --prefix $(VMA_SOURCE_DIR)/build/install
	mv $(VMA_SOURCE_DIR)/build/install/lib/* $(VMA_BUILD_DIR)

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
