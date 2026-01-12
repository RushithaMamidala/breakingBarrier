#pragma once

#include "util/returns.cuh"
#include "data_structs/graph.cuh"

void find_pivots(graph* g, double bound, int k, node_set* source_set, double* distances, pivot_returns* piv_ret);
void dfs_subtree_size(graph* g, int u, int* parent, char* inW, int* subtree_size, char* visited, int* size);
void bmssp(graph* g, int level, double bound, node_set* source_set, int k, int t, double* distances, bmssp_returns* bmssp_ret);
void base_case(graph* g, double bound, int k, node_set* source_set, double* distances, bmssp_returns* base_ret);