# Breaking the Sorting Barrier in Parallel


## Graph

- Undirected: [Condense Matter collaboration network](https://snap.stanford.edu/data/ca-CondMat.html)
- Directed: [Bitcoin OTC trust weighted signed network](https://snap.stanford.edu/data/soc-sign-bitcoin-otc.html)

Other graphs: https://snap.stanford.edu/data/#web

## Build Instructions

From the main directory, run:

`make`



# Execution Instructions
1. Random Sparse graph: `bin.sssp.exe <option 1> <number of nodes> <source node>`

Example:
```
    bin/sssp.exe 1 100 0
```
2. With existing graph: `bin.sssp.exe <option 2> <path to graph> <source node>`

Example:
```
bin/sssp.exe 2 src/graphs/bmssp.txt 0
```

# Graph file format:

```
# Nodes: 6005 Edges: 35592
src, dest, weight
src, dest, weight
.
.
src, dest, weight
```

: )