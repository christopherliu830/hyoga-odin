PROJECT_NAME = Hyoga
RELEXE = build/hyoga.exe
DBGEXE = build/hyoga.debug.exe

VULKAN_DIR = C:\VulkanSDK\1.3.250.1
VMA_SOURCE_DIR = pkgs/VulkanMemoryAllocator
VMA_BUILD_DIR = externals/vma

SHADER_SOURCE_DIR = shaders
SHADER_BUILD_DIR = build/shaders
ODIN_SOURCE_DIR = src

SHADER_COMPILER = glslc
SHADER_FLAGS = -c

ODIN_COMPILER = odin
RELODIN_FLAGS = -out=${RELEXE} -collection:externals=./externals
DBGODIN_FLAGS = -debug -out=${DBGEXE} -vet -collection:externals=./externals

ODIN_SOURCES = $(wildcard $(ODIN_SOURCE_DIR)/*/*.odin)

# List of shader source files and corresponding build targets
SHADER_SOURCES = $(wildcard $(SHADER_SOURCE_DIR)/*.vert $(SHADER_SOURCE_DIR)/*.frag)
SHADER_OBJECTS = $(patsubst \
	$(SHADER_SOURCE_DIR)/%.vert, \
	$(SHADER_BUILD_DIR)/%.vert.spv, \
	$(patsubst $(SHADER_SOURCE_DIR)/%.frag, \
	$(SHADER_BUILD_DIR)/%.frag.spv, \
	$(SHADER_SOURCES)) \
)

# Default target
all: release $(SHADER_OBJECTS) vma

# DEBUG

debug: $(SHADER_OBJECTS) $(DBGEXE) vma

$(DBGEXE): $(ODIN_SOURCES)
	$(ODIN_COMPILER) build $(ODIN_SOURCE_DIR) $(DBGODIN_FLAGS) 


$(DBGVMA_LIB): $(VMA_SOURCE_DIR)
	cmake -S $(VMA_SOURCE_DIR) -B $(VMA_SOURCE_DIR)/build
	msbuild.exe $(VMA_SOURCE_DIR)/build/VulkanMemoryAllocator.sln
	mv $(VMA_SOURCE_DIR)/build/src/Debug/* externals
	mv

# Release
release: $(RELEXE)

$(RELEXE): $(ODIN_SOURCES)
	$(ODIN_COMPILER) build $(ODIN_SOURCE_DIR) $(RELODIN_FLAGS) 


# Prep
install: vma shaders

vma: $(VMA_BUILD_DIR)
$(VMA_BUILD_DIR): $(VMA_SOURCE_DIR)
	cmake -S $(VMA_SOURCE_DIR) -B $(VMA_SOURCE_DIR)/build -DVMA_STATIC_VULKAN_FUNCTIONS=OFF
	msbuild.exe $(VMA_SOURCE_DIR)/build/VulkanMemoryAllocator.sln -p:Configuration=Release
	msbuild.exe $(VMA_SOURCE_DIR)/build/VulkanMemoryAllocator.sln
	mkdir -p $(VMA_BUILD_DIR)
	mv $(VMA_SOURCE_DIR)/build/src/Release/* $(VMA_BUILD_DIR)
	mv $(VMA_SOURCE_DIR)/build/src/Debug/* $(VMA_BUILD_DIR)

shaders: $(SHADER_OBJECTS)

$(SHADER_BUILD_DIR)/%.spv: $(SHADER_SOURCE_DIR)/%
	@mkdir -p $(@D)
	$(SHADER_COMPILER) $(SHADER_FLAGS) $< -o $@
