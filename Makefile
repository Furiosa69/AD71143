SRC_DIR := src
TB_DIR  := tb
OUT_DIR := out
VCD_DIR := vcd

UNISIM := sim_models/xilinx_unisim.v

SRC_FILES := $(SRC_DIR)/nt39565d_ctrl.v \
             $(SRC_DIR)/ad71143_ctrl.v \
             $(SRC_DIR)/ad71143_spi.v \
             $(SRC_DIR)/top.v \
             $(SRC_DIR)/ad71143_data_rx.v \
             $(SRC_DIR)/ad71143_data_rx_dual.v

IVERILOG := iverilog -g2012
VVP      := vvp

OUT_TOP         := $(OUT_DIR)/tb_top.out
OUT_DATA_RX     := $(OUT_DIR)/tb_ad71143_data_rx.out
OUT_DATA_RX_DUAL:= $(OUT_DIR)/tb_ad71143_data_rx_dual.out

all: tb

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

$(VCD_DIR):
	mkdir -p $(VCD_DIR)

tb: $(OUT_DIR) $(VCD_DIR) $(OUT_TOP)
	$(VVP) $(OUT_TOP)

tb_data_rx: $(OUT_DIR) $(VCD_DIR) $(OUT_DATA_RX)
	$(VVP) $(OUT_DATA_RX)

tb_data_rx_dual: $(OUT_DIR) $(VCD_DIR) $(OUT_DATA_RX_DUAL)
	$(VVP) $(OUT_DATA_RX_DUAL)

$(OUT_TOP): $(SRC_FILES) $(TB_DIR)/tb_top.v $(UNISIM)
	$(IVERILOG) -o $@ $(UNISIM) $(SRC_FILES) $(TB_DIR)/tb_top.v

$(OUT_DATA_RX): $(SRC_DIR)/ad71143_data_rx.v $(TB_DIR)/tb_ad71143_data_rx.v $(UNISIM)
	$(IVERILOG) -o $@ $(UNISIM) $(SRC_DIR)/ad71143_data_rx.v $(TB_DIR)/tb_ad71143_data_rx.v

$(OUT_DATA_RX_DUAL): $(SRC_DIR)/ad71143_data_rx.v $(SRC_DIR)/ad71143_data_rx_dual.v $(TB_DIR)/tb_ad71143_data_rx_dual.v $(UNISIM)
	$(IVERILOG) -o $@ $(UNISIM) $(SRC_DIR)/ad71143_data_rx.v $(SRC_DIR)/ad71143_data_rx_dual.v $(TB_DIR)/tb_ad71143_data_rx_dual.v

clean:
	rm -rf $(OUT_DIR)/* $(VCD_DIR)/*.vcd

.PHONY: all tb tb_data_rx tb_data_rx_dual clean
