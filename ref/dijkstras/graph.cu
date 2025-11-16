#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <getopt.h>

typedef struct {
    int u, v;
} edge;

void print_usage() {
    printf("Usage: graph_generator -n <nodes> -e <edges> [-d (directed)] -o <output_file>\n");
}

int edge_exists(edge *edges, int count, int u, int v, int directed) {
    for (int i = 0; i < count; i++) {
        if (edges[i].u == u && edges[i].v == v) return 1;
        if (!directed && edges[i].u == v && edges[i].v == u) return 1;
    }
    return 0;
}

int main(int argc, char* argv[]) {
    int n = 0, e = 0;
    int directed = 0;
    char *output_file = NULL;
    int opt;

    while ((opt = getopt(argc, argv, "n:e:do:")) != -1) {
        switch (opt) {
            case 'n':
                n = atoi(optarg);
                break;
            case 'e':
                e = atoi(optarg);
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

    if (n <= 0 || e <= 0 || output_file == NULL) {
        print_usage();
        return 1;
    }

    FILE *ofs = fopen(output_file, "w");
    if (!ofs) {
        fprintf(stderr, "Error: Cannot open output file\n");
        return 1;
    }

    edge *edges = (edge*)malloc(e * sizeof(edge));
    if (!edges) {
        fprintf(stderr, "Error: Memory allocation failed\n");
        fclose(ofs);
        return 1;
    }

    srand(time(NULL));
    int edge_count = 0;
    while (edge_count < e) {
        int u = rand() % n;
        int v = rand() % n;
        if (u == v) continue;
        if (edge_exists(edges, edge_count, u, v, directed)) continue;

        int w = (rand() % 10) + 1;
        edges[edge_count].u = u;
        edges[edge_count].v = v;
        fprintf(ofs, "%d %d %d\n", u, v, w);
        if (!directed) {
            fprintf(ofs, "%d %d %d\n", v, u, w);
        }
        edge_count++;
    }

    free(edges);
    fclose(ofs);
    printf("Graph generated: %s\n", output_file);
    return 0;
}
