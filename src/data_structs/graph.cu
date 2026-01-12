#include "graph.cuh"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

void init_graph(graph *g, int num_nodes, int num_edges)
{
    // Allocate members
    g->indices     = (int *)malloc((num_nodes + 1) * sizeof(int));
    g->adj_nodes   = (int *)malloc(num_edges * sizeof(int));
    g->weights = (double *)malloc(num_edges * sizeof(double));

    // Set members
    g->num_nodes = num_nodes;
}

void free_graph(graph *g)
{
    // Free members
    free(g->adj_nodes);
    free(g->weights);
    free(g->indices);
}

int size_graph(graph *g)
{
    printf("\n Size of the graph = %d",g->indices[g->num_nodes]);
    return g->indices[g->num_nodes];
}

void print_graph(graph* g)
{
    for (int i = 0; i < g->num_nodes; i++)
    {
        printf("\nNode %d:\n", i);

        int adj_start = g->indices[i];
        int adj_end   = g->indices[i + 1];
        // printf("\n from %d to %d", adj_start, adj_end);
        for (int j = adj_start; j < adj_end; ++j)
        {
            int adj_node = g->adj_nodes[j];
            double weight = g->weights[j];
            printf("-> %d | w = %.2f ",
                   adj_node,
                   weight);
        }
    }
}

void print_csr(graph *g){
    printf("csr is:");
    for (int i = 0; i < g->num_nodes+1; i++){
        printf("%d\t",g->indices[i]);
    }
    printf("\n");
}

graph* generate_graph(int num_nodes, int max_adj, double max_weight)
{
    // Initialize
    graph* g = (graph*)malloc(sizeof(graph*));
    init_graph(g, num_nodes, num_nodes * max_adj);

    // No edges?
    if (max_adj <= 0) { return g; }

    // Current end of array
    int tail = 0;

    // Add all edges
    srand(time(NULL));
    for (int src = 0; src < num_nodes; src++)
    {
        // Set starting index
        g->indices[src] = tail;

        // Number of adjacent nodes (positive)
        int num_adj = (rand() % max_adj) + 1;

        // Add adjacent nodes to src
        for (int i = 0; i < num_adj; i++)
        {
            // Weight (positive)
            double weight = ((double)rand() / RAND_MAX) * (max_weight - 1.0) + 1.0; //(rand() % max_weight) + 1;
            
            // Loop until success
            while (true)
            {
                // Pick random destination
                int dest = rand() % num_nodes;

                // Edge already present?
                bool is_duplicate = false;
                // Loop over adjacent nodes to src that were previously added
                for (int j = g->indices[src]; j < tail; j++)
                {
                    int adj_node = g->indices[src];

                    // Already an edge!
                    if (adj_node == dest)
                    {
                        is_duplicate = true;
                        break;
                    }
                }
                
                // Add the edge?
                if (!is_duplicate)
                {
                    g->adj_nodes[tail] = dest;
                    g->weights[tail] = weight;
                    break;
                }
            }

            // Update the tail
            tail++;
        }
    }

    // Append end of array pointer
    g->indices[num_nodes] = tail;

    // Shrink to the size used
    g->adj_nodes = (int *)realloc(g->adj_nodes, tail * sizeof(int));
    g->weights = (double *)realloc(g->weights, tail * sizeof(double));
    
    return g;
}

// Return: -1 on error, else 0
int add_edge_graph(graph *g, int dest, double weight, int pos)
{   
    // printf("\nAdding %d, %d at pos %d\n",dest, weight, pos);
    // printf("Adding %d %f\n", dest, weight);
    g->adj_nodes[pos] = dest;
    g->weights[pos] = weight;
    // printf("%d",g->weights[pos]);
    return 1;
}

void load_graph(graph* g, char* input_file){
    FILE* ifs = fopen(input_file, "r");
    if (!ifs) {
        fprintf(stderr, "Error: Cannot open input file\n");
    }
    int num_nodes, num_edges;

    if (fscanf(ifs, "# Nodes: %d Edges: %d", &num_nodes, &num_edges) != 2) {
        printf("Error: failed to read graph statistics.\n");
        fclose(ifs);
        return;
    }

    init_graph(g, num_nodes, num_edges);

    int src, dest;
    double weight;
    int edges_added = 0, source = 0, tracker = 0;
    g->indices[tracker] = edges_added;
    ++tracker;
    while (fscanf(ifs, "%d,%d,%lf", &src, &dest, &weight) == 3) {
        while (source!=src-1){
            g->indices[tracker] = edges_added;
            // printf("weight %f", weight);
            ++tracker;
            ++source;
        }
        edges_added += add_edge_graph(g, dest-1, weight, edges_added);
        // printf("Node added: %d\t", nodes_added);
    }
    if (source+1!=num_nodes){
        while(source+1!=num_nodes){
            g->indices[tracker++] = edges_added;
            ++source;
        }
    }
    g->indices[tracker] = edges_added;
    fclose(ifs);
}