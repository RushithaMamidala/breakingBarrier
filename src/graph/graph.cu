#include "graph.cuh"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

void init_adj_list(adj_list_t *a, int max_adj)
{    
    // Allocate members
    a->adj_nodes   = (int *)malloc(max_adj * sizeof(int));
    a->adj_weights = (int *)malloc(max_adj * sizeof(int));

    // Set members
    a->num_adj = 0;
}

void deinit_adj_list(adj_list_t *a)
{
    // Free members
    free(a->adj_nodes);
    free(a->adj_weights);
}

void init_graph(graph_t *g, int num_nodes, int max_adj)
{
    // Allocate members
    g->adj_lists = (adj_list_t *)malloc(num_nodes * sizeof(adj_list_t));

    // Set members
    for (int i = 0; i < num_nodes; i++)
    {
        init_adj_list(&g->adj_lists[i], max_adj);
    }
    g->num_nodes = num_nodes;
    g->max_adj = max_adj;
}

void deinit_graph(graph_t *g)
{
    // Free members
    for (int i = 0; i < g->num_nodes; i++)
    {
        deinit_adj_list(&g->adj_lists[i]);
    }
    free(g->adj_lists);
}

void print_graph(graph_t *g)
{
    for (int i = 0; i < g->num_nodes; i++)
    {
        adj_list_t a = g->adj_lists[i];

        printf("Node %d:\n", i);
        for (int j = 0; j < a.num_adj; j++)
        {
            printf("  --> %d | w = %d\n",
                   a.adj_nodes[j],
                   a.adj_weights[j]);
        }
    }
}

bool is_edge_adj_list(adj_list_t *a, int dest)
{
    for (int i = 0; i < a->num_adj; i++)
    {
        if (a->adj_nodes[i] == dest) { return true; }
    }

    return false;
}

// Warning: Does not test for overflow
// Return: -1 on error, else 0
int add_edge_adj_list(adj_list_t *a, int dest, int weight)
{
    // Edge already exists?
    if (is_edge_adj_list(a, dest)) { return -1; }

    // Add the edge
    a->adj_nodes[a->num_adj] = dest;
    a->adj_weights[a->num_adj] = weight;
    a->num_adj++;

    return 0;
}

// Return: -1 on error, else 0
int add_edge_graph(graph_t *g, int src, int dest, int weight)
{
    // Out of bounds?
    if (src  >= g->num_nodes ||
        dest >= g->num_nodes) { return -1; }
    
    // Get list
    adj_list_t *a = &g->adj_lists[src];

    // Full?
    if (a->num_adj >= g->max_adj) { return -1; }

    // Add the edge
    return add_edge_adj_list(a, dest, weight);
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