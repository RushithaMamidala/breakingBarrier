#pragma once

// Graph (weighted, directed)
typedef struct
{
    int *indices;
    int *adj_nodes;   // num_nodes rows, max_adj columns. -1 = padding.
    double *weights; // num_nodes rows, max_adj columns. -1 = padding.
    int num_nodes;
    // int num_edges;
}
graph;

void init_graph(graph *g, int num_nodes, int num_edges);
void free_graph(graph *g);

void print_graph(graph *g);

void print_csr(graph *g);

int size_graph(graph *g);

int add_edge_graph(graph *g, int dest, double weight, int pos);

graph* generate_graph(int num_nodes, int num_adj, double max_weight=20);

void load_graph(graph* g, char* input_file);