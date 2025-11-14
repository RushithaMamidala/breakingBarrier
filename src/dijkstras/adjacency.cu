#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <getopt.h>

void print_usage() {
    printf("Usage: adjacency_matrix -i <input_edge_list> -n <nodes> [-d (directed)] -o <output_matrix>\n");
}

int main(int argc, char* argv[]) {
    int n = 0;
    int directed = 0;
    char* input_file = NULL;
    char* output_file = NULL;
    int opt;

    while ((opt = getopt(argc, argv, "i:n:do:")) != -1) {
        switch (opt) {
            case 'i':
                input_file = optarg;
                break;
            case 'n':
                n = atoi(optarg);
                break;
            case 'd':
                directed = 1;
                break;
            case 'o':
                output_file = optarg;
                break;
            default:
                print_usage();
                return 1;
        }
    }

    if (n <= 0 || input_file == NULL || output_file == NULL) {
        print_usage();
        return 1;
    }

    int** adj = (int**) malloc(n * sizeof(int*));
    for (int i = 0; i < n; ++i) {
        adj[i] = (int*) malloc(n * sizeof(int));
        for (int j = 0; j < n; ++j) {
            adj[i][j] = (i == j) ? 0 : INT_MAX;
        }
    }

    FILE* ifs = fopen(input_file, "r");
    if (!ifs) {
        fprintf(stderr, "Error: Cannot open input file\n");
        for (int i = 0; i < n; ++i) free(adj[i]);
        free(adj);
        return 1;
    }

    int u, v, w;
    while (fscanf(ifs, "%d %d %d", &u, &v, &w) == 3) {
        adj[u][v] = w;
        if (!directed) adj[v][u] = w;
    }
    fclose(ifs);

    FILE* ofs = fopen(output_file, "w");
    if (!ofs) {
        fprintf(stderr, "Error: Cannot open output file\n");
        for (int i = 0; i < n; ++i) free(adj[i]);
        free(adj);
        return 1;
    }

    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) {
            fprintf(ofs, "%d", (adj[i][j] == INT_MAX ? -1 : adj[i][j]));
            if (j < n-1) fprintf(ofs, " ");
        }
        fprintf(ofs, "\n");
    }
    fclose(ofs);

    for (int i = 0; i < n; ++i) free(adj[i]);
    free(adj);

    printf("Adjacency matrix written to: %s\n", output_file);
    return 0;
}
