#include "graph/graph.cuh"
#include "graph/dijkstras.cuh"
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    if (argc < 4)
    {
        fprintf(stderr, "FORMAT: bmssp <num_nodes> <num_adj> <src>\n");
        return -1;
    }

    // Get args
    int num_nodes = atoi(argv[1]);
    int num_adj   = atoi(argv[2]);
    int src       = atoi(argv[3]);

    // Error handling
    if (num_adj <= 0)
    {
        fprintf(stderr, "Need at least 1 adjacent edge per node!\n");
        return -1;
    }
    if (num_adj >= num_nodes)
    {
        fprintf(stderr, "Adjacent edges must be less than nodes!\n");
        return -1;
    }

    // Make the graph
    graph_t g = generate_graph(num_nodes, num_adj);
    print_graph(&g);

    // Run Dijkstra's
    int *dist_dijk = dijkstras(&g, num_nodes, src);

    // Print
    printf("\n");
    printf("Source: %d\n", src);
    for(int i = 0; i < num_nodes; i++)
    {
        printf("  Node %d: Distance %d\n", i, dist_dijk[i]);
    }

    // Cleanup
    free(dist_dijk);

    return 0;
}
