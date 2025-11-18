#pragma once

// Graph (weighted, directed)
typedef struct
{
    int *adj_nodes;   // num_nodes rows, max_adj columns. -1 = padding.
    int *adj_weights; // num_nodes rows, max_adj columns. -1 = padding.
    int num_nodes;
    int max_adj;
}
graph_t;

void init_graph(graph_t *g, int num_nodes, int max_adj);
void deinit_graph(graph_t *g);

void print_graph(graph_t *g);

int add_edge_graph(graph_t *g, int src, int dest, int weight);

graph_t generate_graph(int num_nodes, int num_adj, int max_weight=20);
