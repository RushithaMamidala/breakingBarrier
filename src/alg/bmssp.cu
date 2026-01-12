#include "data_structs/graph.cuh"
#include "data_structs/min_heap.cuh"
#include "data_structs/pivot_ds.cuh"
#include "util/returns.cuh"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <cuda_runtime.h>
#include <stdint.h>

/**
 * High-level:
 * - This file implements BMSSP (Breaking the Sorting Barrier SSSP) recursion with:
 *   - find_pivots(): builds W (reachable under bound within k relax rounds), then selects pivots P
 *     from the tight-edge forest F inside W.
 *   - base_case(): bounded Dijkstra from a single source until k+1 nodes (or heap empty),
 *     returns U and possibly tightened bound B'.
 *   - bmssp(): recursive BMSSP(l, B, S) routine using pivot data structure D (Lemma 3.3).
 *
 * Note: There is commented-out CUDA code for frontier relaxation; currently CPU relaxation is used.
 */

bool verbose = 0;


// Given parent[] encoding a forest over W (tight-edge forest F), compute subtree sizes.
void dfs_subtree_size(graph* g, int u, int* parent, char* inW, int* subtree_size, char* visited){
    if (visited[u]) return;
    visited[u] = 1;

    int size = 1;
    int start = g->indices[u];
    int end   = g->indices[u + 1];
    for (int e = start; e < end; ++e) {
        int v = g->adj_nodes[e];
        if (v < 0) continue; // padding if any
        if (!inW[v]) continue;
        if (parent[v] == u) {
            dfs_subtree_size(g, v, parent, inW, subtree_size, visited);
            size += subtree_size[v];
        }
    }
    subtree_size[u] = size;
    return;
}

__device__ inline double atomicMinDouble(double* addr, double val) {
    unsigned long long* ull = (unsigned long long*)addr;
    unsigned long long old = *ull, assumed;

    while (true) {
        assumed = old;
        double cur = __longlong_as_double((long long)assumed);
        if (cur <= val) break;                    // no improvement
        unsigned long long desired = __double_as_longlong(val);
        old = atomicCAS(ull, assumed, desired);
        if (old == assumed) break;                // success
    }
    return __longlong_as_double((long long)old);  // previous value
}

__global__ void relax_frontier_nodes(
    int* g_indices,
    int* g_adj_nodes,
    double* g_weights,
    const int* __restrict__ frontier_nodes,
    int frontier_count,
    double* __restrict__ distances,
    double bound,
    int* nodes_to_add
) {
    int j = blockIdx.x * blockDim.x + threadIdx.x;
    if (j >= frontier_count) return;
    extern __shared__ int smem[];
    int* next_count = &smem[0];
    if (threadIdx.x == 0) *next_count = -1;
    __syncthreads();
    int u = frontier_nodes[j];
    if (u < 0 ) return;

    double du = distances[u];

    int start = g_indices[u];
    int end   = g_indices[u + 1];

    for (int a = start; a < end; a++) {
        int v = g_adj_nodes[a];
        if (v < 0) continue;

        double cand = du + g_weights[a];

        // Relax dist[v] atomically
        double old = atomicMinDouble(&distances[v], cand);

        // If we actually improved (or tied) AND under bound, push v to next set
        if (cand <= old && cand < bound) {
            // dedupe (optional but usually helpful)
            int pos = atomicAdd(next_count, 1);
            nodes_to_add[pos] = v;  // may overflow if next_nodes is too small
        }
    }
    if (threadIdx.x == 0) {
        int pos = *next_count;
        nodes_to_add[pos+1] = -1;
    }
}

void find_pivots(graph* g, double bound, int k, node_set* source_set, double* distances, pivot_returns* piv_ret){
    if (verbose) printf("Find pivots called\n");

    // working_set = W, w_cur = current frontier, w_next = next frontier
    node_set* working_set = (node_set*)malloc(sizeof(node_set));
    node_set* w_cur = (node_set*)malloc(sizeof(node_set));
    init_node_set(working_set, g->num_nodes);
    init_node_set(w_cur, g->num_nodes);

    // Initialize W and W0 to S
    copy_node_set(source_set, working_set);
    copy_node_set(source_set, w_cur);

    node_set* w_next = (node_set*)malloc(sizeof(node_set));
    init_node_set(w_next, g->num_nodes); 

    // k relaxation rounds (bounded by "cand < bound" for adding into W sets)
    for( int i=1;i<=k;i++){
        
        // CPU relaxation from current frontier w_cur into w_next
        w_next->count = 0;
        // int threads = 8;
        // int blocks = (w_cur->count + threads - 1) / threads;
        // cudaError_t cuda_ret;

        // int* g_indices;
        // int* g_adj_nodes;
        // double* g_weights;
        // int* nodes_d;
        // int* count_d;
        // double* distances_d;
        // double* bound_d;

        // cuda_ret = cudaMalloc((void**) &g_adj_nodes, g->indices[g->num_nodes]*sizeof(int));
        // if(cuda_ret != cudaSuccess) printf("cudaMalloc(nodes_d, %zu) failed: %s\n", (size_t)w_cur->count * sizeof(int), cudaGetErrorString(cuda_ret));
        // cuda_ret = cudaMalloc((void**) &g_indices, (g->num_nodes+1)*sizeof(int));
        // if(cuda_ret != cudaSuccess) printf("cudaMalloc(nodes_d, %zu) failed: %s\n", (size_t)w_cur->count * sizeof(int), cudaGetErrorString(cuda_ret));
        // cuda_ret = cudaMalloc((void**) &g_weights, g->indices[g->num_nodes] * sizeof(double));
        // if(cuda_ret != cudaSuccess) printf("Unable to allocate device memory4\n");
        // cuda_ret = cudaMalloc((void**) &nodes_d, w_cur->count * sizeof(int));
        // if(cuda_ret != cudaSuccess) printf("Unable to allocate device memory2\n");
        // cuda_ret = cudaMalloc((void**) &count_d, sizeof(int));
        // if(cuda_ret != cudaSuccess) printf("Unable to allocate device memory3\n");
        // cuda_ret = cudaMalloc((void**) &distances_d, g->num_nodes * sizeof(double));
        // if(cuda_ret != cudaSuccess) printf("Unable to allocate device memory4\n");
        // cuda_ret = cudaMalloc((void**) &bound_d, sizeof(double));
        // if(cuda_ret != cudaSuccess) printf("Unable to allocate device memory5\n");

        // int* nodes_to_add = NULL;
        // cuda_ret = cudaMalloc((void**) &nodes_to_add, g->indices[g->num_nodes] * sizeof(int));

        // cudaDeviceSynchronize();

        // cuda_ret = cudaMemcpy(g_adj_nodes, g->adj_nodes, g->indices[g->num_nodes]*sizeof(int), cudaMemcpyHostToDevice);
        // if(cuda_ret != cudaSuccess) printf("Unable to copy memory to device1\n");
        // cuda_ret = cudaMemcpy(g_indices, g->indices, (g->num_nodes+1)*sizeof(int), cudaMemcpyHostToDevice);
        // if(cuda_ret != cudaSuccess) printf("Unable to copy memory to device1\n");
        // cuda_ret = cudaMemcpy(g_weights, g->weights, g->indices[g->num_nodes]*sizeof(int), cudaMemcpyHostToDevice);
        // if(cuda_ret != cudaSuccess) printf("Unable to copy memory to device1\n");
        // cuda_ret = cudaMemcpy(nodes_d, w_cur->nodes, w_cur->count*sizeof(int), cudaMemcpyHostToDevice);
        // if(cuda_ret != cudaSuccess) printf("Unable to copy memory to device2\n");
        // cuda_ret = cudaMemcpy(count_d, &w_cur->count, sizeof(int), cudaMemcpyHostToDevice);
        // if(cuda_ret != cudaSuccess) printf("Unable to copy memory to device3\n");
        // cuda_ret = cudaMemcpy(distances_d, distances, g->num_nodes * sizeof(double), cudaMemcpyHostToDevice);
        // if(cuda_ret != cudaSuccess) printf("Unable to copy memory to device4\n");
        // cuda_ret = cudaMemcpy(bound_d, &bound, sizeof(double), cudaMemcpyHostToDevice);
        // if(cuda_ret != cudaSuccess) printf("Unable to copy memory to device5\n");

        // size_t shmem_bytes = sizeof(int);
        // relax_frontier_nodes<<<blocks, threads, shmem_bytes>>>(
        //     g_indices,
        //     g_adj_nodes,
        //     g_weights,
        //     w_cur->nodes,
        //     w_cur->count,
        //     distances,
        //     bound,
        //     nodes_to_add
        // );
        // cuda_ret = cudaDeviceSynchronize();
        // int* nodes_to_add_host = (int*)malloc(sizeof(int)*g->num_nodes);
        // cuda_ret = cudaMemcpy(nodes_to_add_host, nodes_to_add, sizeof(int)*g->num_nodes, cudaMemcpyDeviceToHost);
        // for(int idx = 0;;idx++){
        //     if (nodes_to_add_host[idx]==-1) break;
        //     node_set_add(w_next, nodes_to_add_host[idx]);
        //     node_set_add(working_set, nodes_to_add_host[idx]);
        // }

        for(int j=0; j<w_cur->count;j++){
            int u = w_cur->nodes[j];
            
            double du = distances[u];
            int start = g->indices[u];
            int end = g->indices[u+1];
            for(int a=start; a<end; a++){
                int v = g->adj_nodes[a];
                if (v < 0) continue;  // padding if any
                double w_uv = g->weights[a];
                double cand = du + w_uv;
                // Relax and update distance if improved (or tied)
                if (cand <= distances[v]) {
                    // 8: db[v] ← db[u] + wuv
                    distances[v] = cand;
                    // Only expand into sets if cand is strictly under bound
                    // 9: if distances[u] + wuv < B then 
                    if (cand < bound) {
                        // 10: Wi ← Wi ∪ {v}
                        node_set_add(w_next, v);
                        // 11: W ← W ∪ Wi   (we will add incrementally)
                        node_set_add(working_set, v);
                    }
                }
            }
        }
        // Prepare for next iteration: Wi becomes Wi-1
        copy_node_set(w_next, w_cur);
    }
    // w0 no longer needed
    free_node_set(w_cur);

    node_set* pivots = (node_set*)malloc(sizeof(node_set));
    init_node_set(pivots, g->num_nodes);
    // Early exit condition: if |W| > k|S| then P=S
    if (working_set->count > k * source_set->count){
        if (verbose) print_node_set(working_set);
        copy_node_set(source_set, pivots); 
        piv_ret->p = pivots; //P ← S
        piv_ret->w = working_set;

        return;  // 14: return P , W
    }
    
    /* Build the tight-edge forest F:
    F = {(u,v) : dist[v] = dist[u] + w(u,v), u,v ∈ W}.
    Under Assumption 2.1, each v has at most one incoming tight edge,
    so F forms a directed forest and parent[v] is well-defined.*/
    int* parent = (int*)malloc(g->num_nodes * sizeof(int));
    for (int i = 0; i < g->num_nodes; ++i) parent[i] = -1;

    for (int idx = 0; idx < working_set->count; ++idx) {
        int u = working_set->nodes[idx];
        double du = distances[u];
        int start = g->indices[u];
        int end   = g->indices[u + 1];

        for (int e = start; e < end; ++e) {
            int v = g->adj_nodes[e];
            if (v < 0) continue;
            if (!working_set->in_set[v]) continue;   // both u, v must be in W
            double w_uv = g->weights[e];

            // tight edge: db[v] = db[u] + w_uv
            double cand = du + w_uv;
            if (cand == distances[v]) {
                // By Assumption 2.1, at most one incoming tight edge.
                parent[v] = u;
            }
        }
    }
    // 16: P ← {u ∈ S : u is a root of a tree with ≥ k vertices in F}
    int* subtree_size = (int*)calloc(g->num_nodes, sizeof(int));
    char* visited     = (char*)calloc(g->num_nodes, sizeof(char));

    for (int idx = 0; idx < source_set->count; ++idx) {
        int u = source_set->nodes[idx];
        if (!working_set->in_set[u]) continue;      // must be in W to be part of F
        if (parent[u] != -1) continue; // root must have no parent

        dfs_subtree_size(g, u, parent, working_set->in_set, subtree_size, visited);
        if (subtree_size[u] >= k) {
            node_set_add(pivots, u);
        }
    }
    // Cleanup local arrays (working_set and pivots are returned)
    free(parent);
    free(subtree_size);
    free(visited);

    piv_ret->p = pivots;
    piv_ret->w = working_set;
    return;
}

/**
 * base_case:
 * Base case of BMSSP when level == 0.
 *
 * Requirement: source_set has exactly one node x.
 * Runs a bounded Dijkstra-like expansion from x under cutoff "cand < bound"
 * until either heap empty or we have collected k+1 nodes into U0.
 *
 * Output:
 *  - If |U0| <= k: return (U=U0, bound stays as input bound).
 *  - Else: set B' = max_{u in U0} dist[u], and return
 *      U = { u in U0 : dist[u] < B' }   (strictly less)
 *    and bound = B'.
 **/

void base_case(graph* g, double bound, int k, node_set* source_set, double* distances, bmssp_returns* base_ret){
    if (verbose) printf("Base case called with bound = %.2f Source set: ", bound);
    if (verbose) print_node_set(source_set);
    if (verbose) printf("\n");
    if(source_set->count != 1){
        printf("\n Invalid base_case call! %d nodes in the source set",source_set->count);
        exit(0);
    }
    int x = source_set->nodes[0];
    // U0: discovered nodes (bounded)
    node_set* U0 = (node_set*)malloc(sizeof(node_set)); 
    init_node_set(U0, g->num_nodes);
    node_set_add(U0, x);
    // Min-heap for Dijkstra expansions
    min_heap* H = (min_heap*)malloc(sizeof(min_heap)); 
    init_min_heap(H,g->num_nodes);
    // Start from x with its current distance value
    push_min_heap(H, x, distances[x]);
    
    // Expand until k+1 nodes are in U0 or heap empties
    while (!is_empty_heap(H) && U0->count < k + 1) {
        min_heap_node p = heap_top(H); pop_min_heap(H);
        int u = p.node; double d = p.dist;
        node_set_add(U0, u);
        // Relax outgoing edges
        int start = g->indices[u];
        int end = g->indices[u+1];
        for(int a=start; a<end; a++){
            int v = g->adj_nodes[a];
            if (v < 0) continue;  // padding if any
            double w_uv = g->weights[a];
            double cand = d + w_uv;
            // Standard relax + cutoff by bound
            if (cand <= distances[v] && cand < bound) {
                distances[v] = cand;
                push_min_heap(H, v, distances[v]);
            }
        }
        
    }
    // Cleanup heap
    free_min_heap(H);

    // Return based on size
    if (U0->count <= k) {
        base_ret->bound = bound;
        base_ret->U = U0;
    } else {
        // Tighten bound to the maximum distance among U0
        double B_dash = -1;
        // compute Bd = max dhat[u] over U0
        for (int idx = 0; idx < U0->count; ++idx) {
            int key = U0->nodes[idx];
            if (distances[key] > B_dash) B_dash = distances[key];
        }
        // U = { u in U0 : dist[u] < B' }
        node_set* U = (node_set*)malloc(sizeof(node_set)); 
        init_node_set(U, g->num_nodes);
        for (int idx = 0; idx < U0->count; ++idx) {
            int key = U0->nodes[idx];
            if (distances[key] < B_dash) node_set_add(U, key);
        }
        base_ret->bound = B_dash;
        base_ret->U = U;
    }

    return;
}

/**
 * bmssp:
 * Recursive BMSSP routine:
 *  - level = recursion depth l
 *  - bound = current cutoff B
 *  - source_set = S (complete vertices set at this recursion)
 *  - distances[] = global tentative distances (dhat / db), updated in-place
 *  - returns:
 *      bmssp_ret->bound : new tightened bound B'
 *      bmssp_ret->U     : set U of "settled/complete" vertices with dist < B'
 *
 * Steps (informal):
 * 1) If level == 0: base_case.
 * 2) Find pivots P and working set W via find_pivots().
 * 3) Initialize pivot data structure D with M = 2^{(l-1)t} and insert pivots with their distances.
 * 4) Loop:
 *      - Pull (B_i, S_i) from D
 *      - Recurse BMSSP(l-1, B_i, S_i)
 *      - Append returned U_i into U
 *      - Relax edges out of U_i and either:
 *          a) Insert into D if dist in [B_i, B)
 *          b) Add to K if dist in [B'_0, B_i)
 *      - Also add nodes from S_i into K if their dist in [B'_0, B_i)
 *      - Batch prepend K into D
 * 5) Finish:
 *      - Set output bound = min(B, B'_0)
 *      - Add all nodes in W with dist < output bound into U
 */
void bmssp(graph* g, int level, double bound, node_set* source_set, int k, int t, double* distances, bmssp_returns* bmssp_ret){
    cudaDeviceSynchronize();
    if (verbose) printf("\nBMSSP called with k = %d, t = %d, level = %d, bound = %.2f, source = ", k, t, level, bound);
    if (verbose) print_node_set(source_set);
    if (verbose) printf("\n");

    if (level == 0) return base_case(g, bound, k, source_set, distances, bmssp_ret);
    
    // Find pivots P and working set W
    pivot_returns* piv_ret = (pivot_returns*)malloc(sizeof(pivot_returns));
    find_pivots(g, bound, k, source_set, distances, piv_ret);
    node_set* pivots = piv_ret->p;
    if (verbose) printf("Obtained pivots: ");
    if (verbose) print_node_set(pivots);
    if (verbose) printf("Obtained working set: ");
    if (verbose) print_node_set(piv_ret->w);
    
    double B_0_dash;
    int M = pow(2, (level-1)*t);
    // Initialize pivot DS D with M = 2^{(level-1)*t}
    pivot_ds *D = pivotds_create(M, bound, g->num_nodes);
    
    // Insert pivots into D and compute initial B'_0 = min dist among pivots
    if (pivots->count == 0) B_0_dash = bound;
    else{
        if (verbose) printf("Inserting pivots\n");
        for(int i = 0; i < pivots->count;i++){
            int node = pivots->nodes[i];
            pivotds_insert(D, node, distances[node]);
        }
        // Compute minimum pivot distance
        B_0_dash = distances[pivots->nodes[0]];
        for(int i=0; i<pivots->count;i++){
            if (distances[pivots->nodes[i]]<B_0_dash) B_0_dash = distances[pivots->nodes[i]];
        }
    }
    // U accumulates all returned U_i across pulls
    node_set* U = (node_set*)malloc(sizeof(node_set));
    init_node_set(U, g->num_nodes);
    int i=0;
    // Main loop: repeat pulls until U has enough nodes or D becomes empty
    while(U->count < k * pow(2,level * t) && !is_empty_pivotds(D)){
        
        ++i;
        bmssp_returns* B_i;
        if (verbose) printf("Before pull\n");
        if (verbose) pivotds_print(D, 0);
        // Pull a batch S_i with associated bound B_i from D
        B_i  = pivotds_pull(D);
        // printf("Pivots are: \n",i);
        if (verbose) printf("After pull\n");
        if (verbose) pivotds_print(D, 0);
        double bound_i = B_i->bound;
        // If pull returned empty set, terminate (additional precaution)
        if (B_i->U->count == 0) break;
        bmssp_returns* bmssp_ret_dash = (bmssp_returns*)malloc(sizeof(bmssp_returns));
        // Recurse on (level-1, bound_i, S_i)
        bmssp(g, level-1, bound_i, B_i->U, k, t, distances,bmssp_ret_dash);
        // Update B'_0 from recursion return
        B_0_dash = bmssp_ret_dash->bound;
        if (verbose) printf("Returned from higher level with B%d' = %.2f\n",i,B_0_dash);
        // U_i returned by recursion
        node_set* U_i = bmssp_ret_dash->U;
        // Add U_i into U
        append_node_set(U, U_i);
        // K collects nodes to be batch-prepended (with distances in [B'_0, bound_i))
        node_set* K = (node_set*)malloc(sizeof(node_set));
        init_node_set(K, g->num_nodes);
        /**
         * Relax edges out of U_i:
         * - If cand improves dist[v], update dist[v].
         * - If cand in [bound_i, bound): insert into D
         * - Else if cand in [B'_0, bound_i): add to K (unless already in U)
         */
        for(int j=0;j<U_i->count;j++){
            int u = U_i->nodes[j];
            double du = distances[u];
            int start = g->indices[u];
            int end   = g->indices[u + 1];

            for (int e = start; e < end; ++e) {
                int v = g->adj_nodes[e];
                double w_uv = g->weights[e];
                double dv = distances[v];
                double cand = du + w_uv;
                if(cand <= dv){
                    distances[v] = cand;
                    // Case A: reinsert into D if in [B_i, B)
                    if(bound_i<= cand && cand < bound){
                        pivotds_insert(D, v, cand);
                    }
                    // Case B: add to K if in [B'_0, B_i)
                    else if(B_0_dash<= cand && cand < bound_i){
                        if (U->in_set[v]) continue;
                        node_set_add(K, v);
                    }
                }
            }
        }
        
        node_set* S_i = B_i->U;
        // add any x in S_i whose distance is in [B'_0, bound_i) to K.
        if (S_i->count!=0){
            int x;
            double dx;
            for (int j = 0; j<S_i->count; j++){
                x = S_i->nodes[j];
                dx = distances[x];
                if (B_0_dash<= dx && dx < bound_i){
                    node_set_add(K, x);
                }
            }
        }
        /**
         * Batch prepend K into D:
         **/
        if(K->count!=0){
            data_pair* kay = (data_pair*)malloc(sizeof(data_pair)*K->count);
            for(int a = 0; a < K->count; a++){
                kay[a].key = K->nodes[a];
                kay[a].val = distances[K->nodes[a]];
            }
            pivotds_batch_prepend(D, kay, K->count);   
        }

    }
    // Finalize the new bound
    double mini = bound <= B_0_dash ? bound : B_0_dash; 
    bmssp_ret->bound = mini;
    // all nodes in W with dist < mini into U (completes them for this level)
    for(int a = 0; a<piv_ret->w->count; a++){
        int x = piv_ret->w->nodes[a];
        if (distances[x] < mini) node_set_add(U, x);
    }
    if (verbose) printf("U is:");
    if (verbose) print_node_set(U);
    bmssp_ret->U = U;
    return;

}