SRC_DIR := src
TB_DIR  := tb
OUT_DIR := out
VCD_DIR := vcd

SRC_FILES := $(wildcard $(SRC_DIR)/ad71143_data_rx.v)
TB_FILES  := $(wildcard $(TB_DIR)/tb_ad71143_data_rx.v)

IVERILOG := iverilog -g2012
VVP      := vvp

OUT_TOP := $(OUT_DIR)/tb_ad71143_data_rx.out

all: tb

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

$(VCD_DIR):
	mkdir -p $(VCD_DIR)

tb: $(OUT_DIR) $(VCD_DIR) $(OUT_TOP)
	$(VVP) $(OUT_TOP)

$(OUT_TOP): $(SRC_FILES) $(TB_DIR)/tb_ad71143_data_rx.v
	$(IVERILOG) -o $@ $(SRC_FILES) $(TB_DIR)/tb_ad71143_data_rx.v

clean:
	rm -rf $(OUT_DIR)/* $(VCD_DIR)/*.vcd

.PHONY: all tb clean
