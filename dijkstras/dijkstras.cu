#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <cuda_runtime.h>
#include <getopt.h>
#include <time.h>
#include <thrust/device_ptr.h>
#include <thrust/reduce.h>
#include <thrust/functional.h>

#define INF 1000000000

__global__ void dijkstra_kernel(int* adj, int* dist, int* pred, bool* updated, int n) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= n) return;
    for (int v = 0; v < n; ++v) {
        int weight = adj[tid * n + v];
        if (weight != INF && dist[tid] != INF) {
            int new_dist = dist[tid] + weight;
            int old_dist = atomicMin(&dist[v], new_dist);
            if (new_dist < old_dist) {
                pred[v] = tid;
                updated[v] = true;
            }
        }
    }
}

void print_usage() {
    printf("Usage: dijkstra_cuda -i <adj_matrix> -s <source> -n <nodes>\n");
}

int main(int argc, char* argv[]) {
    int n = 0, source = 0;
    char* input_file = NULL;
    int opt;
    while ((opt = getopt(argc, argv, "i:s:n:")) != -1) {
        switch (opt) {
            case 'i': input_file = optarg; break;
            case 's': source = atoi(optarg); break;
            case 'n': n = atoi(optarg); break;
            default: print_usage(); return 1;
        }
    }
    if (n <= 0 || input_file == NULL || source < 0 || source >= n) {
        print_usage();
        return 1;
    }

    int* h_adj = (int*) malloc(n * n * sizeof(int));
    int* h_dist = (int*) malloc(n * sizeof(int));
    int* h_pred = (int*) malloc(n * sizeof(int));
    bool* h_updated = (bool*) malloc(n * sizeof(bool));
    if (!h_adj || !h_dist || !h_pred || !h_updated) {
        fprintf(stderr, "Memory allocation error\n");
        free(h_adj); free(h_dist); free(h_pred); free(h_updated);
        return 1;
    }

    FILE* ifs = fopen(input_file, "r");
    if (!ifs) {
        fprintf(stderr, "Error: Cannot open input file\n");
        free(h_adj); free(h_dist); free(h_pred); free(h_updated);
        return 1;
    }
    for (int i = 0; i < n * n; ++i) {
        int val;
        if (fscanf(ifs, "%d", &val) != 1) val = -1;
        h_adj[i] = (val == -1 ? INF : val);
    }
    fclose(ifs);

    for (int i = 0; i < n; ++i) {
        h_dist[i] = INF;
        h_pred[i] = -1;
        h_updated[i] = false;
    }
    h_dist[source] = 0;

    int *d_adj, *d_dist, *d_pred;
    bool *d_updated;
    bool anyUpdated;
    thrust::device_ptr<bool> dev_updated(d_updated);
    cudaMalloc(&d_adj, n * n * sizeof(int));
    cudaMalloc(&d_dist, n * sizeof(int));
    cudaMalloc(&d_pred, n * sizeof(int));
    cudaMalloc(&d_updated, n * sizeof(bool));
    cudaMemcpy(d_adj, h_adj, n * n * sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(d_dist, h_dist, n * sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(d_pred, h_pred, n * sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(d_updated, h_updated, n * sizeof(bool), cudaMemcpyHostToDevice);

    clock_t start = clock();
    do {
        anyUpdated = false;
        cudaMemset(d_updated, 0, n * sizeof(bool));
        dijkstra_kernel<<<(n + 255) / 256, 256>>>(d_adj, d_dist, d_pred, d_updated, n);
        cudaDeviceSynchronize();

        anyUpdated = thrust::reduce(thrust::device, d_updated, d_updated + n, false, thrust::logical_or<bool>());
    } while (anyUpdated);
    clock_t end = clock();

    cudaMemcpy(h_dist, d_dist, n * sizeof(int), cudaMemcpyDeviceToHost);
    cudaMemcpy(h_pred, d_pred, n * sizeof(int), cudaMemcpyDeviceToHost);

    printf("Dijkstra (CUDA) completed in %.6f seconds.\n", (double)(end - start) / CLOCKS_PER_SEC);
    printf("\nNodes: \n");
    for (int i = 0; i < n; ++i) printf("%d ", i);
    printf("\nDistances from source %d: \n", source);
    for (int i = 0; i < n; ++i) printf("%d ", (h_dist[i] == INF) ? -1 : h_dist[i]);
    printf("\nPredecessors: \n");
    for (int i = 0; i < n; ++i) printf("%d ", h_pred[i]);
    printf("\n");

    cudaFree(d_adj); cudaFree(d_dist); cudaFree(d_pred); cudaFree(d_updated);
    free(h_adj); free(h_dist); free(h_pred); free(h_updated);

    return 0;
}
