#!/bin/bash

echo '----------------- nvcc Info: -------------------'
nvcc --version

echo '----------------- Compiling --------------------'
SCRIPT1=$1
SCRIPT2=$2
mkdir -p "$HOME/tmp"
export TMPDIR=${SLURM_TMPDIR:-$HOME/tmp}
nvcc "$SCRIPT1" -o exe --ptxas-options=-v
shift

echo '----------------- Executing --------------------'
srun -v --exclusive \
     -p ClsParSystems \
     --reservation=Fall2025Class_ClsParSystems \
     --time=1:00:00 \
     --gres=gpu:TitanX:8 \
     ./exe "$@"