#include "graph.cuh"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

void init_graph(graph_t *g, int num_nodes, int max_adj)
{
    // Allocate members
    g->adj_nodes   = (int *)malloc(num_nodes * max_adj * sizeof(int));
    g->adj_weights = (int *)malloc(num_nodes * max_adj * sizeof(int));

    // Set members
    for (int i = 0; i < num_nodes * max_adj; i++)
    {
        g->adj_weights[i] = -1;
        g->adj_nodes[i] = -1;
    }
    g->num_nodes = num_nodes;
    g->max_adj = max_adj;
}

void deinit_graph(graph_t *g)
{
    // Free members
    free(g->adj_nodes);
    free(g->adj_weights);
}

void print_graph(graph_t *g)
{
    for (int i = 0; i < g->num_nodes; i++)
    {
        printf("Node %d:\n", i);
        for (int j = 0; j < g->max_adj; j++)
        {
            int adj_node = g->adj_nodes[g->max_adj * i + j];
            int adj_weight = g->adj_weights[g->max_adj * i + j];

            // End of list early?
            if (adj_node == -1) { break; }

            printf("  --> %d | w = %d\n",
                   adj_node,
                   adj_weight);
        }
    }
}

// Return: -1 on error, else 0
int add_edge_graph(graph_t *g, int src, int dest, int weight)
{
    // Out of bounds?
    if (src  >= g->num_nodes ||
        dest >= g->num_nodes) { return -1; }
    
    for (int j = 0; j < g->max_adj; j++)
    {
        int *adj_node = &g->adj_nodes[g->max_adj * src + j];
        int *adj_weight = &g->adj_weights[g->max_adj * src + j];

        // Empty space?
        if (*adj_node == -1)
        {
            // Add the edge
            *adj_node = dest;
            *adj_weight = weight;

            return 0;
        }

        // Already present?
        if (*adj_node == dest)
        {
            return -1;
        }
    }

    // Full!
    return -1;
}

graph_t generate_graph(int num_nodes, int num_adj, int max_weight)
{
    // Initialize
    graph_t g;
    init_graph(&g, num_nodes, num_adj);

    // No edges?
    if (num_adj <= 0) { return g; }

    // Add all edges
    srand(time(NULL));
    for (int src = 0; src < num_nodes; src++) {
        for (int i = 0; i < num_adj; i++)
        {
            // Positive weight
            int weight = (rand() % max_weight) + 1;

            // Loop until success
            int fail = true;
            while (fail)
            {
                // Add edge to random dest
                int dest = rand() % num_nodes;
                fail = add_edge_graph(&g, src, dest, weight);
            }
        }
    }
    
    return g;
}