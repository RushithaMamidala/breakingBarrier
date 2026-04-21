#include "bptree.cuh"
#include "bptree_kernels.cuh"
#include <cuda_runtime.h>
#include <cstdio>
#include <cstdlib>

// ---------------------------------------------------------------------------
// Cooperative (all-thread) parallel search within an internal node.
// Each thread checks one stripe of separator keys.
// Returns the child index to follow.  All threads get the same result.
// blockDim.x threads cooperate; uses shared memory scratch (caller provides).
// ---------------------------------------------------------------------------
__device__
int32_t bp_find_child_parallel(const BPPool* pool, const BPNode& n,
                                float k, int32_t* smem_scratch)
{
    // smem_scratch must be at least blockDim.x int32_ts.
    int tid = threadIdx.x;
    int T   = blockDim.x;
    int num_keys = n.count;

    // Each thread scans its stripe and finds the last sep_key <= k
    // Store the local "insertion point" upper bound.
    int32_t local_hi = 0;
    for (int i = tid; i < num_keys; i += T) {
        if (bp_sep_key(pool, n, i) <= k) local_hi = i + 1;
    }
    smem_scratch[tid] = local_hi;
    __syncthreads();

    // Parallel reduction: max across all threads = global insertion point
    for (int s = T >> 1; s > 0; s >>= 1) {
        if (tid < s) {
            if (smem_scratch[tid + s] > smem_scratch[tid])
                smem_scratch[tid] = smem_scratch[tid + s];
        }
        __syncthreads();
    }
    return smem_scratch[0]; // child index
}

// ---------------------------------------------------------------------------
// Choose thread-block size based on block capacity.
// Returns the smallest power-of-2 >= capacity, clamped to [32, 1024].
// ---------------------------------------------------------------------------
inline int bp_choose_block_threads(int block_capacity) {
    int t = 32;
    while (t < block_capacity && t < 1024) t <<= 1;
    return t;
}

// ---------------------------------------------------------------------------
// Allocate and initialize a B+ tree on the GPU.
//
// Parameters:
//   node_pool_size   : total BPNode slots pre-allocated
//   nid_pool_size    : total int32 slots for leaf node_id storage
//   child_pool_size  : total int32 slots for internal child arrays
//   key_pool_size    : total float slots for key storage
//   max_ops          : max parallel operations per kernel launch
//   max_block_cap    : max leaf block capacity (for scratch buffer sizing)
//   init_block_cap   : capacity of the initial root leaf
// ---------------------------------------------------------------------------
BPTreeHost* bp_create(
    int32_t node_pool_size,
    int32_t nid_pool_size,
    int32_t child_pool_size,
    int32_t key_pool_size,
    int32_t max_ops,
    int32_t max_block_cap,
    int32_t init_block_cap)
{
    BPTreeHost* h = new BPTreeHost();
    h->max_ops       = max_ops;
    h->max_block_cap = max_block_cap;

    // Allocate device memory
    CUDA_CHECK(cudaMalloc((void**)&h->d_nodes, sizeof(BPNode)  * node_pool_size));
    CUDA_CHECK(cudaMalloc((void**)&h->d_node_ids, sizeof(int32_t) * nid_pool_size));
    CUDA_CHECK(cudaMalloc((void**)&h->d_children, sizeof(int32_t) * child_pool_size));
    CUDA_CHECK(cudaMalloc((void**)&h->d_keys, sizeof(float)   * key_pool_size));

    CUDA_CHECK(cudaMalloc((void**)&h->d_out_node_ids, sizeof(int32_t) * max_ops * max_block_cap));
    CUDA_CHECK(cudaMalloc((void**)&h->d_out_counts, sizeof(int32_t) * max_ops));
    CUDA_CHECK(cudaMalloc((void**)&h->d_out_keys, sizeof(float)   * max_ops));
    CUDA_CHECK(cudaMalloc((void**)&h->d_full_leaves, sizeof(int32_t) * max_ops));
    CUDA_CHECK(cudaMalloc((void**)&h->d_parent_full, sizeof(int32_t) * max_ops));
    CUDA_CHECK(cudaMalloc((void**)&h->d_pool, sizeof(BPPool)));

    // Pinned host buffers
    CUDA_CHECK(cudaMallocHost((void**)&h->h_out_node_ids, sizeof(int32_t) * max_ops * max_block_cap));
    CUDA_CHECK(cudaMallocHost((void**)&h->h_out_counts, sizeof(int32_t) * max_ops));
    CUDA_CHECK(cudaMallocHost((void**)&h->h_out_keys, sizeof(float)   * max_ops));
    CUDA_CHECK(cudaMallocHost((void**)&h->h_full_leaves, sizeof(int32_t) * max_ops));
    CUDA_CHECK(cudaMallocHost((void**)&h->h_parent_full, sizeof(int32_t) * max_ops));

    // Build host-side BPPool to copy to device
    BPPool host_pool;
    host_pool.nodes         = h->d_nodes;
    host_pool.node_capacity = node_pool_size;
    host_pool.node_top      = 0;
    host_pool.node_id_pool  = h->d_node_ids;
    host_pool.nid_capacity  = nid_pool_size;
    host_pool.nid_top       = 0;
    host_pool.child_pool    = h->d_children;
    host_pool.child_capacity = child_pool_size;
    host_pool.child_top     = 0;
    host_pool.key_pool      = h->d_keys;
    host_pool.key_capacity  = key_pool_size;
    host_pool.key_top       = 0;
    host_pool.root          = BP_NULL_IDX;
    host_pool.leaf_head     = BP_NULL_IDX;
    host_pool.pop_cursor    = BP_NULL_IDX;

    CUDA_CHECK(cudaMemcpy(h->d_pool, &host_pool, sizeof(BPPool), cudaMemcpyHostToDevice));

    // Initialize root leaf on device via a tiny kernel
    // We use a simple 1-thread setup kernel
    auto init_root = [&]() {
        // Temporarily do on host by reading/writing pool fields directly
        // Allocate root leaf index = 0 (node_top was 0)
        int32_t root_idx = 0;

        // We'll call a device-side init via a helper kernel
        // For simplicity, set up pool state from host then launch a 1-thread kernel
        // that calls bp_init_leaf.
        struct InitArgs { BPPool* pool; int32_t idx; int32_t cap; };
        // Inline lambda as a global kernel is not possible in a header,
        // so we do it via cudaMemcpy of pool fields after manual arithmetic.

        // Manually advance node_top and nid_top and key_top on host mirror:
        // node 0: nid_offset=0 (cap slots), key_offset=0 (1 slot)
        BPPool updated = host_pool;
        updated.node_top = 1;
        updated.nid_top  = init_block_cap;
        updated.key_top  = 1;
        updated.root     = root_idx;
        updated.leaf_head = root_idx;
        updated.pop_cursor = root_idx;
        CUDA_CHECK(cudaMemcpy(h->d_pool, &updated, sizeof(BPPool), cudaMemcpyHostToDevice));

        // Build BPNode for root leaf
        BPNode root_node;
        root_node.capacity       = init_block_cap;
        root_node.count          = 0;
        root_node.parent         = BP_NULL_IDX;
        root_node.flags          = 1u; // leaf
        root_node.node_id_offset = 0;
        root_node.child_offset   = BP_NULL_IDX;
        root_node.key_offset     = 0;
        root_node.next_leaf      = BP_NULL_IDX;
        root_node.prev_leaf      = BP_NULL_IDX;
        root_node.lock           = 0;
        root_node._pad[0]        = 0;
        root_node._pad[1]        = 0;
        CUDA_CHECK(cudaMemcpy(h->d_nodes, &root_node, sizeof(BPNode), cudaMemcpyHostToDevice));

        // Initialize key_pool[0] = FLT_MAX
        float init_key = FLT_MAX;
        CUDA_CHECK(cudaMemcpy(h->d_keys, &init_key, sizeof(float), cudaMemcpyHostToDevice));
    };
    init_root();

    return h;
}

// ---------------------------------------------------------------------------
// Free all device and host memory
// ---------------------------------------------------------------------------
void bp_destroy(BPTreeHost* h) {
    cudaFree(h->d_nodes);
    cudaFree(h->d_node_ids);
    cudaFree(h->d_children);
    cudaFree(h->d_keys);
    cudaFree(h->d_out_node_ids);
    cudaFree(h->d_out_counts);
    cudaFree(h->d_out_keys);
    cudaFree(h->d_full_leaves);
    cudaFree(h->d_parent_full);
    cudaFree(h->d_pool);
    cudaFreeHost(h->h_out_node_ids);
    cudaFreeHost(h->h_out_counts);
    cudaFreeHost(h->h_out_keys);
    cudaFreeHost(h->h_full_leaves);
    cudaFreeHost(h->h_parent_full);
    delete h;
}

// ---------------------------------------------------------------------------
// Launch: pop num_pops minimum blocks
//
// Blocks the CPU until results are ready.
// Returns results in h->h_out_node_ids, h->h_out_counts, h->h_out_keys.
// h->h_out_counts[i] == -1 means the tree was empty for that pop.
// ---------------------------------------------------------------------------
void bp_pop(BPTreeHost* h, int32_t num_pops, int32_t block_cap, cudaStream_t stream) {
    if (num_pops <= 0) return;
    int T    = bp_choose_block_threads(block_cap);
    int smem = T * sizeof(int32_t);
    bp_pop_kernel<<<num_pops, T, smem, stream>>>(
        h->d_pool, num_pops, h->max_block_cap,
        h->d_out_node_ids, h->d_out_counts, h->d_out_keys);
    CUDA_CHECK(cudaMemcpyAsync(h->h_out_node_ids, h->d_out_node_ids,
        sizeof(int32_t) * num_pops * h->max_block_cap, cudaMemcpyDeviceToHost, stream));
    CUDA_CHECK(cudaMemcpyAsync(h->h_out_counts, h->d_out_counts,
        sizeof(int32_t) * num_pops, cudaMemcpyDeviceToHost, stream));
    CUDA_CHECK(cudaMemcpyAsync(h->h_out_keys, h->d_out_keys,
        sizeof(float) * num_pops, cudaMemcpyDeviceToHost, stream));
    CUDA_CHECK(cudaStreamSynchronize(stream));
}

// ---------------------------------------------------------------------------
// Launch: insert num_inserts (key, node_id) pairs
//
// After insertion, checks for full leaves and runs splits iteratively
// until no more splits are needed (handles split propagation up the tree).
// ---------------------------------------------------------------------------
void bp_insert(BPTreeHost* h,
               const float*   h_keys,
               const int32_t* h_node_ids,
               int32_t        num_inserts,
               int32_t        block_cap,
               cudaStream_t   stream)
{
    if (num_inserts <= 0) return;

    // Upload inputs
    float*   d_keys;
    int32_t* d_nids;
    CUDA_CHECK(cudaMalloc((void**)&d_keys, sizeof(float)   * num_inserts));
    CUDA_CHECK(cudaMalloc((void**)&d_nids, sizeof(int32_t) * num_inserts));
    CUDA_CHECK(cudaMemcpyAsync(d_keys, h_keys,     sizeof(float)   * num_inserts, cudaMemcpyHostToDevice, stream));
    CUDA_CHECK(cudaMemcpyAsync(d_nids, h_node_ids, sizeof(int32_t) * num_inserts, cudaMemcpyHostToDevice, stream));

    int T    = bp_choose_block_threads(block_cap);
    int smem = T * sizeof(int32_t);

    printf("Calling insertion kernel...\n");

    bp_insert_kernel<<<num_inserts, T, smem, stream>>>(
        h->d_pool, num_inserts, d_keys, d_nids, h->d_full_leaves);

    // // Check for synchronous launch errors
    // cudaError_t errSync = cudaGetLastError();
    // if (errSync != cudaSuccess) 
    //     printf("Sync error: %s\n", cudaGetErrorString(errSync));

    // // Check for asynchronous execution errors
    // cudaError_t errAsync = cudaDeviceSynchronize();
    // if (errAsync != cudaSuccess) 
    //     printf("Async error: %s\n", cudaGetErrorString(errAsync));

    cudaFree(d_keys);
    cudaFree(d_nids);

    printf("!!! Skipping the splitting pass !!!\n");
    return;

    printf("Splitting any filled blocks...\n");

    // --- Iterative split propagation ---
    int32_t* d_current_input = h->d_full_leaves; 

    while (true) {
        // TODO: Reconsider if deduping is necessary. If so, make efficient.

        // Copy results to host for deduping
        CUDA_CHECK(cudaMemcpyAsync(h->h_full_leaves, d_current_input,
            sizeof(int32_t) * num_inserts, cudaMemcpyDeviceToHost, stream));
        CUDA_CHECK(cudaStreamSynchronize(stream));

        // Dedupe
        int32_t split_buf[4096];
        int32_t n_splits = 0;
        for (int i = 0; i < num_inserts && n_splits < 4096; i++) {
            int32_t idx = h->h_full_leaves[i];
            if (idx == BP_NULL_IDX) continue;
            
            bool dup = false;
            for (int j = 0; j < n_splits; j++) {
                if (split_buf[j] == idx) { dup = true; break; }
            }
            if (!dup) split_buf[n_splits++] = idx;
        }

        if (n_splits == 0) break; // SUCCESSFUL TERMINATION

        // Reuse preallocated device scratch instead of cudaMalloc
        CUDA_CHECK(cudaMemcpyAsync(h->d_parent_full, split_buf, 
            sizeof(int32_t) * n_splits, cudaMemcpyHostToDevice, stream));

        // Check if the first node is a leaf to decide which kernel to run
        BPNode sample;
        CUDA_CHECK(cudaMemcpy(&sample, h->d_nodes + split_buf[0], sizeof(BPNode), cudaMemcpyDeviceToHost));

        if (bp_is_leaf(sample)) {
            int Ts = bp_choose_block_threads(block_cap);
            bp_split_kernel<<<n_splits, Ts, Ts * sizeof(int32_t), stream>>>(
                h->d_pool, n_splits, h->d_parent_full, h->d_full_leaves);
        } else {
            bp_split_internal_kernel<<<n_splits, 1, 0, stream>>>(
                h->d_pool, n_splits, h->d_parent_full, h->d_full_leaves);
        }

        // Prepare for next level: the output of this split (h->d_full_leaves) 
        // becomes the input for the next check.
        d_current_input = h->d_full_leaves;
        num_inserts = n_splits;
    }
}
