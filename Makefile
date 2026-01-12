# COMPILER SETTINGS ----------------------------------------------------------

OUT = bin

CC = nvcc
INC = -Isrc
FLG = -g $(INC)

# BUILD ----------------------------------------------------------------------

IGNORE := \

SRC_C  = $(filter-out $(IGNORE), $(shell find src/ -name "*.c"))
SRC_CU = $(filter-out $(IGNORE), $(shell find src/ -name "*.cu"))
SRC = $(SRC_C) $(SRC_CU)

HDR_C  = $(shell find src/ -name "*.h")
HDR_CU = $(shell find src/ -name "*.cuh")
HDR = $(HDR_C) $(HDR_CU)

OBJ_C  = $(patsubst src/%.c,  obj/%.o, $(SRC_C))
OBJ_CU = $(patsubst src/%.cu, obj/%.o, $(SRC_CU))
OBJ = $(OBJ_C) $(OBJ_CU)

obj/%.o: src/%.c
	mkdir -p $(dir $@)
	$(CC) -c $< -o $@ $(FLG)

obj/%.o: src/%.cu
	mkdir -p $(dir $@)
	$(CC) -c $< -o $@ $(FLG)

# TARGETS --------------------------------------------------------------------

all: sssp pivot_ds_test

sssp: $(OBJ)
	$(CC) $(FLG) main/sssp.cu -o $(OUT)/$@.exe --ptxas-options=-v $^

# block_list_test: $(OBJ)
# 	$(CC) $(FLG) main/block_list_test.cu -o $(OUT)/$@.exe $^

pivot_ds_test: $(OBJ)
	$(CC) $(FLG) main/pivot_ds_test.cu -o $(OUT)/$@.exe $^

.PHONY: clean
clean:
	rm -rf obj/* bin/*
