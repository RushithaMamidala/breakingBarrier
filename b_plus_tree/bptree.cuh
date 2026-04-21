#pragma once
#include <cuda_runtime.h>
#include <assert.h>
#include <float.h>
#include <stdint.h>

// ---------------------------------------------------------------------------
// Error checking macro
// ---------------------------------------------------------------------------
#define CUDA_CHECK(call)                                                    \
    do {                                                                    \
        cudaError_t _e = (call);                                            \
        if (_e != cudaSuccess) {                                            \
            fprintf(stderr, "CUDA error %s:%d: %s\n",                       \
                    __FILE__, __LINE__, cudaGetErrorString(_e));            \
            exit(EXIT_FAILURE);                                             \
        }                                                                   \
    } while (0)

// ---------------------------------------------------------------------------
// Compile-time constants
// ---------------------------------------------------------------------------
#define BP_NULL_IDX  (-1)          // sentinel for "no node"
#define BP_MAX_TREE_HEIGHT  32     // supports up to 2^32 leaves

// ---------------------------------------------------------------------------
// Node layout
//
// All nodes live in a flat pool.  "Pointers" are int32_t pool indices.
//
// Internal node:
//   keys[0..num_keys-1]   : separator keys (float), num_keys <= capacity
//   children[0..num_keys] : pool indices of children, num_keys+1 entries
//
// Leaf node:
//   keys[0]               : minimum distance key of this block
//   node_ids[0..count-1]  : graph node IDs stored in this block
//   next_leaf             : pool index of next leaf (for linked-list traversal)
//   prev_leaf             : pool index of prev leaf
//
// We use a tagged union so both types live in the same pool.
// The `is_leaf` flag distinguishes them.
//
// Variable block size: `capacity` is stored per-node and set at alloc time.
// node_ids is a pointer into a separate flat int32_t array (node_id_pool).
// Each node owns a contiguous slice of node_id_pool; the slice offset is
// stored in `node_id_offset`.  On split, two new slices are carved out.
// ---------------------------------------------------------------------------

struct alignas(16) BPNode {
    // --- common header (16 bytes) ---
    int32_t  capacity;       // max node_ids (leaf) or max children-1 (internal)
    int32_t  count;          // current occupancy
    int32_t  parent;         // pool index of parent, BP_NULL_IDX for root
    uint32_t flags;          // bit 0 = is_leaf, bit 1 = locked, bit 2 = deleted

    // --- variable-length data pointers (pool offsets) ---
    // For a leaf:   node_ids live at node_id_pool[node_id_offset .. +capacity]
    // For internal: children live at child_pool[child_offset .. +capacity+1]
    //               sep keys live at key_pool[key_offset .. +capacity]
    int32_t  node_id_offset; // offset into flat node_id_pool  (leaf only)
    int32_t  child_offset;   // offset into flat child_pool     (internal only)
    int32_t  key_offset;     // offset into flat key_pool       (both)

    // --- leaf linked list ---
    int32_t  next_leaf;      // BP_NULL_IDX if rightmost
    int32_t  prev_leaf;      // BP_NULL_IDX if leftmost

    // --- spinlock (used as mutex for this node) ---
    // 0 = unlocked, 1 = locked
    int32_t  lock;

    // padding to 48 bytes total (cache-friendly)
    int32_t  _pad[2];
};

// ---------------------------------------------------------------------------
// Pool descriptor — lives in device memory, one instance per tree
// ---------------------------------------------------------------------------
struct BPPool {
    // node pool
    BPNode*  nodes;
    int32_t  node_capacity;   // total nodes pre-allocated
    int32_t  node_top;        // atomic: next free node index

    // flat int32 pool for leaf node_ids
    int32_t* node_id_pool;
    int32_t  nid_capacity;    // total slots
    int32_t  nid_top;         // atomic: next free slot

    // flat int32 pool for internal node children
    int32_t* child_pool;
    int32_t  child_capacity;
    int32_t  child_top;       // atomic

    // flat float pool for separator keys (both leaf key and internal keys)
    float*   key_pool;
    int32_t  key_capacity;
    int32_t  key_top;         // atomic

    // tree root
    int32_t  root;            // pool index of root node

    // leaf linked-list head (minimum leaf)
    int32_t  leaf_head;       // pool index of leftmost leaf

    // pop cursor: index into leaf linked list for multi-pop
    // (we traverse via next_leaf pointers starting from leaf_head)
    int32_t  pop_cursor;      // atomic
};

// ---------------------------------------------------------------------------
// Host-visible pool descriptor (mirrors device BPPool, owns the memory)
// ---------------------------------------------------------------------------
struct BPTreeHost {
    BPPool* d_pool;         // device pointer to BPPool struct

    // Device buffers (owned here, referenced inside d_pool)
    BPNode*  d_nodes;
    int32_t* d_node_ids;
    int32_t* d_children;
    float*   d_keys;

    // Scratch buffers for kernel outputs
    int32_t* d_out_node_ids;   // [max_ops * max_block_cap]
    int32_t* d_out_counts;     // [max_ops]
    float*   d_out_keys;       // [max_ops]
    int32_t* d_full_leaves;    // [max_ops]
    int32_t* d_parent_full;    // [max_ops]

    int32_t max_ops;
    int32_t max_block_cap;    // upper bound on block capacity for scratch sizing

    // Pinned host mirrors for reading results back
    int32_t* h_out_node_ids;
    int32_t* h_out_counts;
    float*   h_out_keys;
    int32_t* h_full_leaves;
    int32_t* h_parent_full;
};

// ---------------------------------------------------------------------------
// Status helpers
// ---------------------------------------------------------------------------

__host__ __device__ __forceinline__ bool bp_is_leaf(const BPNode& n) {
    return (n.flags & 1u) != 0;
}

__device__ __forceinline__ bool bp_is_deleted(const BPNode& n) {
    return (n.flags & 4u) != 0;
}

// ---------------------------------------------------------------------------
// Per-node spinlock acquire/release
// All threads in the block call these collectively when they need to lock a
// node.  Only lane 0 does the CAS; result is broadcast via shared memory or
// return value.  Caller must __syncthreads() as needed.
// ---------------------------------------------------------------------------

// Acquire: only call from a single designated thread (e.g. lane 0).
// Spins until the lock is acquired.
__device__ __forceinline__ void bp_lock(BPNode* node) {
    while (atomicCAS(&node->lock, 0, 1) != 0) {
        // spin — yield to other warps
        __nanosleep(32);
    }
    __threadfence(); // ensure all subsequent reads see post-lock state
}

// Release: only call from the thread that acquired the lock.
__device__ __forceinline__ void bp_unlock(BPNode* node) {
    __threadfence(); // ensure all writes are visible before unlock
    atomicExch(&node->lock, 0);
}

// ---------------------------------------------------------------------------
// Pool allocation helpers (atomic, called by a single thread)
// ---------------------------------------------------------------------------

__device__ __forceinline__
int32_t bp_alloc_node(BPPool* pool) {
    int32_t idx = atomicAdd(&pool->node_top, 1);
    assert(idx < pool->node_capacity);
    return idx;
}

__device__ __forceinline__
int32_t bp_alloc_nids(BPPool* pool, int32_t count) {
    int32_t off = atomicAdd(&pool->nid_top, count);
    assert(off + count <= pool->nid_capacity);
    return off;
}

__device__ __forceinline__
int32_t bp_alloc_children(BPPool* pool, int32_t count) {
    int32_t off = atomicAdd(&pool->child_top, count);
    assert(off + count <= pool->child_capacity);
    return off;
}

__device__ __forceinline__
int32_t bp_alloc_keys(BPPool* pool, int32_t count) {
    int32_t off = atomicAdd(&pool->key_top, count);
    assert(off + count <= pool->key_capacity);
    return off;
}

// ---------------------------------------------------------------------------
// Initialize a fresh leaf node (called by a single thread after alloc)
// ---------------------------------------------------------------------------
__device__ __forceinline__
void bp_init_leaf(BPPool* pool, int32_t idx, int32_t capacity, int32_t parent) {
    BPNode& n       = pool->nodes[idx];
    n.capacity      = capacity;
    n.count         = 0;
    n.parent        = parent;
    n.flags         = 1u; // is_leaf
    n.node_id_offset = bp_alloc_nids(pool, capacity);
    n.child_offset  = BP_NULL_IDX;
    n.key_offset    = bp_alloc_keys(pool, 1); // one key: the min distance
    n.next_leaf     = BP_NULL_IDX;
    n.prev_leaf     = BP_NULL_IDX;
    n.lock          = 0;
    n._pad[0]       = 0;
    n._pad[1]       = 0;
    pool->key_pool[n.key_offset] = FLT_MAX; // empty block: key = +inf
}

// ---------------------------------------------------------------------------
// Initialize a fresh internal node (called by a single thread after alloc)
// ---------------------------------------------------------------------------
__device__ __forceinline__
void bp_init_internal(BPPool* pool, int32_t idx, int32_t capacity, int32_t parent) {
    BPNode& n        = pool->nodes[idx];
    n.capacity       = capacity;
    n.count          = 0; // number of separator keys (children = count+1)
    n.parent         = parent;
    n.flags          = 0u; // internal
    n.node_id_offset = BP_NULL_IDX;
    n.child_offset   = bp_alloc_children(pool, capacity + 1);
    n.key_offset     = bp_alloc_keys(pool, capacity);
    n.next_leaf      = BP_NULL_IDX;
    n.prev_leaf      = BP_NULL_IDX;
    n.lock           = 0;
    n._pad[0]        = 0;
    n._pad[1]        = 0;
}

// ---------------------------------------------------------------------------
// Key accessors
// ---------------------------------------------------------------------------

// Leaf: single key = minimum distance of nodes in this block
__device__ __forceinline__
float bp_leaf_key(const BPPool* pool, const BPNode& n) {
    return pool->key_pool[n.key_offset];
}

__device__ __forceinline__
void bp_set_leaf_key(BPPool* pool, BPNode& n, float key) {
    pool->key_pool[n.key_offset] = key;
}

// Internal: separator keys[0..count-1]
__device__ __forceinline__
float bp_sep_key(const BPPool* pool, const BPNode& n, int32_t i) {
    return pool->key_pool[n.key_offset + i];
}

__device__ __forceinline__
void bp_set_sep_key(BPPool* pool, BPNode& n, int32_t i, float key) {
    pool->key_pool[n.key_offset + i] = key;
}

// Internal: children[0..count]
__device__ __forceinline__
int32_t bp_child(const BPPool* pool, const BPNode& n, int32_t i) {
    return pool->child_pool[n.child_offset + i];
}

__device__ __forceinline__
void bp_set_child(BPPool* pool, BPNode& n, int32_t i, int32_t child_idx) {
    pool->child_pool[n.child_offset + i] = child_idx;
}

// ---------------------------------------------------------------------------
// Binary search helpers (single thread)
//
// For internal nodes: find child index for key k.
// Returns i such that sep[i-1] <= k < sep[i], i.e. go to children[i].
// ---------------------------------------------------------------------------
__device__ __forceinline__
int32_t bp_find_child(const BPPool* pool, const BPNode& n, float k) {
    // Linear scan — parallelized version in kernels uses thread-striped search
    int32_t lo = 0, hi = n.count; // n.count sep keys → n.count+1 children
    while (lo < hi) {
        int32_t mid = (lo + hi) >> 1;
        if (bp_sep_key(pool, n, mid) <= k) lo = mid + 1;
        else hi = mid;
    }
    return lo; // child index
}


// ---------------------------------------------------------------------------
// Functions
// ---------------------------------------------------------------------------
__device__
int32_t bp_find_child_parallel(const BPPool* pool, const BPNode& n,
                                float k, int32_t* smem_scratch);

BPTreeHost* bp_create(
    int32_t node_pool_size,
    int32_t nid_pool_size,
    int32_t child_pool_size,
    int32_t key_pool_size,
    int32_t max_ops,
    int32_t max_block_cap,
    int32_t init_block_cap);

void bp_destroy(BPTreeHost* h);

void bp_pop(BPTreeHost* h, int32_t num_pops, int32_t block_cap, cudaStream_t stream = 0);

void bp_insert(BPTreeHost* h,
               const float*   h_keys,
               const int32_t* h_node_ids,
               int32_t        num_inserts,
               int32_t        block_cap,
               cudaStream_t   stream = 0);