#include "data_structs/graph.cuh"
#include "alg/dijkstras.cuh"
#include "alg/bmssp.cuh"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char **argv)
{
    if (argc<4) {
        printf("Usage 1: %s <option> <num_nodes> <Source node>\n", argv[0]);
        printf("Usage 2: %s <option> <graph_file> <Source node>\n", argv[0]);
        return 1;
    }
    
    graph* g;
    int num_nodes;
    int option = atoi(argv[1]);
    switch(option){
        case 1:{
            num_nodes = atoi(argv[2]);
            int max_adj = 5;
            int max_weight = 20;
            g = generate_graph(num_nodes, max_adj, max_weight);
            break;
        }
        case 2:{
            printf("Loading the graph from file\n");
            char *filename = argv[2];
            FILE *fp = fopen(filename, "r");
            if (!fp) {
                printf("Error: could not open file %s\n", filename);
                return 1;
            }

            g = (graph *)malloc(sizeof(graph));
            load_graph(g, filename);
            // printf("\n%d",g->weights[0]);
            break;
        }
        default:break;
    }
    print_graph(g);
    print_csr(g);
    // Run Dijkstra's
    int src = atoi(argv[3]);
    double* dist_dijk = dijkstras(g, src);
    if (dist_dijk==NULL){
        printf("\ndijkstras failed\n");
        return 0;
    }

    // // Print
    printf("\n");
    printf("Source: %d\n\nDijkstras distances:\n", src);
    for(int i = 0; i < g->num_nodes; i++)
    {
        if (dist_dijk[i] == 100000000){
            printf("%d -> %d, %d\t", src, i, -1);
            continue;
        }
        printf("%d -> %d, %.2f\t", src, i, dist_dijk[i]);
    }
    printf("\n");
    cudaDeviceSynchronize();

    double ln = log2(g->num_nodes);       // compute log(n) as double
    // printf("ln(%d) = %f\n", g->num_nodes,ln);
    int k = floor(pow(ln, 1.0/3.0));        // floor is implicit by cast
    int t = floor(pow(ln, 2.0/3.0));
    int level = ceil(ln/t);
    double bound = 100000000;

    node_set* source_set = (node_set*)malloc(sizeof(node_set));
    init_node_set(source_set, g->num_nodes);
    node_set_add(source_set, src);

    // printf("\nStarting BMSSP with k = %d, t = %d, level = %d\n", k, t, level);
    double* distances = (double*)malloc(g->num_nodes*sizeof(double));
    for(int i = 0; i < g->num_nodes; i++) distances[i] = 100000000;
    distances[src]=0;
    bmssp_returns* bmssp_ret = (bmssp_returns*)malloc(sizeof(bmssp_returns*));// = (bmssp_returns*)malloc(sizeof(bmssp_returns));
    bmssp(g, level, bound, source_set, k, t, distances, bmssp_ret);
    
    // for(int i = 0; i < bmssp_ret->U->count;i++){
    //     printf("%d\t", bmssp_ret->U->nodes[i]);
    // }
    // printf("\n");
    printf("\nBMSSP:\n");
    for(int i = 0; i < g->num_nodes; i++)
    {
        if (distances[i] == 100000000){
            printf("%d -> %d, %d\t", src, i, -1);
            continue;
        }
        printf("%d -> %d, %.2f\t", src, i, distances[i]);
    }
    printf("\n");

    printf("\nCompare dijkstras vs bmssp\n");
    for(int i = 0; i < g->num_nodes; i++)
    {
        printf("%d -> %d (%.2f)\t",src,i,distances[i]-dist_dijk[i]);
    }
    printf("\n");
    // // Cleanup
    // free(dist_dijk);
    // free_graph(g);
    
    return 0;
}
