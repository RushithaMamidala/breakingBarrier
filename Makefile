# COMPILER SETTINGS ----------------------------------------------------------

OUT = bin

CC = nvcc
INC = -Isrc
FLG = -g $(INC)

# BUILD ----------------------------------------------------------------------

SRC_C  = $(shell find src/ -name "*.c")
SRC_CU = $(shell find src/ -name "*.cu")
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

all: sssp

sssp: $(OBJ)
	$(CC) $(FLG) main/sssp.cu -o $(OUT)/$@.exe $^

.PHONY: clean
clean:
	rm -rf obj/* bin/*
