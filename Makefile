SRC_DIR  := src
TB_DIR   := tb
OUT_DIR  := out

SRC_FILES := $(wildcard $(SRC_DIR)/*.v)
TB_FILES  := $(wildcard $(TB_DIR)/tb*.v)

IVERILOG := iverilog -g2012
VVP      := vvp

OUT_NORMAL      := $(OUT_DIR)/tb_nt39565d_normal_short_stv.out
OUT_2G          := $(OUT_DIR)/tb_nt39565d_2g_short_stv.out
OUT_2GLCS2_ID   := $(OUT_DIR)/tb_nt39565d_2glcs2_identical_stv.out
OUT_2GLCS2_DEL  := $(OUT_DIR)/tb_nt39565d_2glcs2_delay1cpv_stv.out


$(OUT_DIR):
	mkdir -p $(OUT_DIR)

all: mode1

mode1: $(OUT_DIR) $(OUT_NORMAL)
	$(VVP) $(OUT_NORMAL)

$(OUT_NORMAL): $(SRC_FILES) $(TB_DIR)/tb_nt39565d_normal_short_stv.v
	$(IVERILOG) -o $@ $(SRC_FILES) $(TB_DIR)/tb_nt39565d_normal_short_stv.v

mode2: $(OUT_DIR) $(OUT_2G)
	$(VVP) $(OUT_2G)

$(OUT_2G): $(SRC_FILES) $(TB_DIR)/tb_nt39565d_2g_short_stv.v
	$(IVERILOG) -o $@ $(SRC_FILES) $(TB_DIR)/tb_nt39565d_2g_short_stv.v

mode3: $(OUT_DIR) $(OUT_2GLCS2_ID)
	$(VVP) $(OUT_2GLCS2_ID)

$(OUT_2GLCS2_ID): $(SRC_FILES) $(TB_DIR)/tb_nt39565d_2glcs2_identical_stv.v
	$(IVERILOG) -o $@ $(SRC_FILES) $(TB_DIR)/tb_nt39565d_2glcs2_identical_stv.v

mode4: $(OUT_DIR) $(OUT_2GLCS2_DEL)
	$(VVP) $(OUT_2GLCS2_DEL)

$(OUT_2GLCS2_DEL): $(SRC_FILES) $(TB_DIR)/tb_nt39565d_2glcs2_delay1cpv_stv.v
	$(IVERILOG) -o $@ $(SRC_FILES) $(TB_DIR)/tb_nt39565d_2glcs2_delay1cpv_stv.v

clean:
	rm -rf $(OUT_DIR)/*  *.vcd

.PHONY: all mode1 mode2 mode3 mode4 clean
