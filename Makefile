# COMPILER SETTINGS ----------------------------------------------------------

OUT = bin/bmssp.exe

CC = nvcc
INC = -Isrc
FLG = -g $(INC)

# BUILD ----------------------------------------------------------------------

SRC_C = $(shell find src/ -name "*.c")
SRC_CU  = $(shell find src/ -name "*.cu")
SRC = $(SRC_CPP) $(SRC_CU)

HDR_C = $(shell find src/ -name "*.h")
HDR_CU  = $(shell find src/ -name "*.cuh")
HDR = $(HDR_CPP) $(HDR_CU)

OBJ_CPP = $(pathsubst src/%.cpp, obj/%.o, $(SRC))
OBJ_CU  = $(pathsubst src/%.cu,  obj/%.o, $(SRC))
OBJ = $(OBJ_CPP) $(OBJ_CU)

obj/%.o: src/%.cpp
         @mkdir -p $(dir $@)
         $(CC) -c $< -o $@ $(FLG)

obj/%.o: src/%.cu
         @mkdir -p $(dir $@)
         $(CC) -c $< -o $@ $(FLG)

# TARGETS --------------------------------------------------------------------

# Default
$(OUT): $(OBJ)
        $(CC) $(FLG) -o $@ $(OBJ)

.PHONY: clean
clean:
       rm -rf obj/* bin/*
