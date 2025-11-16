#ifndef GRAPH_CUH
#define GRAPH_CUH

// Adjacency list
typedef struct
{
    int *adj_nodes;
    int *adj_weights;
    int num_adj;
}
adj_list_t;

// Graph (weighted, directed)
typedef struct
{
    adj_list_t *adj_lists;
    int num_nodes;
    int max_adj;
}
graph_t;

void init_graph(graph_t *g, int num_nodes, int max_adj);
void deinit_graph(graph_t *g);

void print_graph(graph_t *g);

int add_edge_graph(graph_t *g, int src, int dest, int weight);

graph_t generate_graph(int num_nodes, int num_adj, int max_weight=20);

#endif
