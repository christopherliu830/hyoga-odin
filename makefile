PROJECT_NAME = Hyoga

SHADER_SOURCE_DIR = shaders
SHADER_BUILD_DIR = build/shaders
ODIN_SOURCE_DIR = src

SHADER_COMPILER = glslc
SHADER_FLAGS = -c

ODIN_COMPILER = odin
ODIN_FLAGS = -debug -out=build/hyoga.exe

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
all: $(SHADER_OBJECTS) build/odenpi.exe

# Compile shaders and move to build folder
$(SHADER_BUILD_DIR)/%.spv: $(SHADER_SOURCE_DIR)/%
	@mkdir -p $(@D)
	$(SHADER_COMPILER) $(SHADER_FLAGS) $< -o $@

# Compile Odin program
build/odenpi.exe: $(ODIN_SOURCES)
	$(ODIN_COMPILER) build $(ODIN_SOURCE_DIR) $(ODIN_FLAGS) 

shaders: shaders
	glslc 

watch:
	@echo "Watching for shader changes..."
	@while true; do \
		find $(SHADER_SOURCE_DIR) -type f -name '*.vert' -o -name '*.frag' | entr -d make all; \
	done

.PHONY: all watch