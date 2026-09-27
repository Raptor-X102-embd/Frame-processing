# ============================================================
# Tools
# ============================================================
VERILATOR ?= verilator
GTKWAVE   ?= gtkwave

# ============================================================
# Directories and files
# ============================================================
BUILD_DIR := build

RTL_SRC_DIR := rtl/src
RTL_HDR_DIR := rtl/headers
TB_DIR      := tb

# Source files
RTL_SRCS := $(wildcard $(RTL_SRC_DIR)/*.sv)
RTL_HDRS := $(wildcard $(RTL_HDR_DIR)/*.svh)
TB_SRC   := $(TB_DIR)/tb_top.sv

# Include directories (для img_pkg.svh)
INCDIRS := -I$(RTL_HDR_DIR)

# Executable name
SIM_BIN := $(BUILD_DIR)/tb_top

# ============================================================
# Verilator flags
# ============================================================
VERILATOR_FLAGS  = -sv --timing --trace --binary -Wall
VERILATOR_FLAGS += -Wno-fatal
VERILATOR_FLAGS += -Wno-TIMESCALEMOD
VERILATOR_FLAGS += -Wno-IMPORTSTAR
#VERILATOR_FLAGS += -Wno-ASCRANGE
#VERILATOR_FLAGS += -Wno-PROCASSINIT
#VERILATOR_FLAGS += -Wno-UNUSEDPARAM
#VERILATOR_FLAGS += -Wno-UNDRIVEN
VERILATOR_FLAGS += $(INCDIRS)

# ============================================================
# Targets
# ============================================================
.PHONY: all sim build wave clean

all: sim

# Запуск симуляции (сборка + выполнение)
sim: $(SIM_BIN)
	@echo "========================================="
	@echo " Running simulation..."
	@echo "========================================="
	@mkdir -p $(BUILD_DIR)
	./$(SIM_BIN)

# Только сборка исполняемого файла
build: $(SIM_BIN)

$(SIM_BIN): $(RTL_SRCS) $(RTL_HDRS) $(TB_SRC)
	@mkdir -p $(BUILD_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module tb_top --Mdir $(BUILD_DIR) -o tb_top $(RTL_SRCS) $(TB_SRC)
	@echo "Build completed. Executable: $(SIM_BIN)"

# Открыть временные диаграммы (если в тестбенче есть $dumpvars)
wave:
	$(GTKWAVE) $(BUILD_DIR)/wave.vcd &

# Очистка артефактов сборки
clean:
	rm -rf $(BUILD_DIR) obj_dir
