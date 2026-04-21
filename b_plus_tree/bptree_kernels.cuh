#pragma once
#include "bptree.cuh"
#include <stdio.h>

// ---------------------------------------------------------------------------
// Shared memory layout helpers
//
// Each kernel is launched as:
//   grid  = (num_ops, 1, 1)
//   block = (block_threads, 1, 1)   where block_threads is a multiple of 32
//
// block_threads is chosen by the host based on current B+ tree block size:
//   block_threads = min(1024, next_power_of_2(block_capacity))
//   but at least 32.
//
// threadIdx.x == "tid" throughout.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// KERNEL: bp_pop_kernel
//
// Each thread block pops one leaf block from the minimum end of the tree.
// "Popping" means:
//   1. Atomically claim the current leaf_head (or advance pop_cursor).
//   2. Cooperatively copy its node_ids to the output buffer.
//   3. Mark the leaf deleted.
//   4. Update leaf_head to next_leaf.
//
// Output:
//   out_node_ids[op * max_block_cap .. +count] : node IDs from popped block
//   out_counts[op]                             : how many node IDs were popped
//   out_keys[op]                               : the min-distance key of block
//
// If no leaf is available (tree empty), out_counts[op] = -1.
// ---------------------------------------------------------------------------
__global__ void bp_pop_kernel(
    BPPool*  pool,
    int32_t  num_ops,
    int32_t  max_block_cap,   // stride for out_node_ids
    int32_t* out_node_ids,    // [num_ops * max_block_cap]
    int32_t* out_counts,      // [num_ops]
    float*   out_keys         // [num_ops]
)
{
    int op  = blockIdx.x;
    int tid = threadIdx.x;
    int T   = blockDim.x;
    if (op >= num_ops) return;

    // Shared state for this block
    __shared__ int32_t s_leaf_idx;
    __shared__ int32_t s_count;
    __shared__ float   s_key;

    // --- Step 1: thread 0 atomically claims a leaf ---
    if (tid == 0) {
        s_leaf_idx = BP_NULL_IDX;

        // Spin until we claim a non-deleted leaf or exhaust the list
        while (true) {
            int32_t cur = atomicAdd(&pool->pop_cursor, 0); // read
            if (cur == BP_NULL_IDX) break;

            // Try to advance pop_cursor to next_leaf atomically
            BPNode& leaf = pool->nodes[cur];
            int32_t nxt  = leaf.next_leaf;

            // CAS: if pop_cursor is still `cur`, advance it
            int32_t old = atomicCAS(&pool->pop_cursor, cur, nxt);
            if (old != cur) continue; // someone else advanced it, retry

            // We own `cur`. Check if already deleted by another pop.
            // Use lock to ensure exclusive ownership.
            bp_lock(&leaf);
            if (!bp_is_deleted(leaf)) {
                // Mark deleted
                leaf.flags |= 4u;
                s_leaf_idx  = cur;
                s_count     = leaf.count;
                s_key       = bp_leaf_key(pool, leaf);
                bp_unlock(&leaf);

                // Unlink from leaf list (update prev's next pointer)
                if (leaf.prev_leaf != BP_NULL_IDX) {
                    BPNode& prev = pool->nodes[leaf.prev_leaf];
                    bp_lock(&prev);
                    prev.next_leaf = leaf.next_leaf;
                    bp_unlock(&prev);
                }
                if (leaf.next_leaf != BP_NULL_IDX) {
                    BPNode& next = pool->nodes[leaf.next_leaf];
                    bp_lock(&next);
                    next.prev_leaf = leaf.prev_leaf;
                    bp_unlock(&next);
                }
                // Update leaf_head if we popped the head
                atomicCAS(&pool->leaf_head, cur, nxt);
                break;
            }
            bp_unlock(&leaf);
            // Leaf was already deleted (raced with another pop), continue
        }
    }
    __syncthreads();

    int32_t leaf_idx = s_leaf_idx;
    if (leaf_idx == BP_NULL_IDX) {
        if (tid == 0) out_counts[op] = -1;
        return;
    }

    // --- Step 2: cooperatively copy node_ids to output ---
    BPNode& leaf    = pool->nodes[leaf_idx];
    int32_t count   = s_count;
    int32_t src_off = leaf.node_id_offset;
    int32_t dst_off = op * max_block_cap;

    for (int i = tid; i < count; i += T) {
        out_node_ids[dst_off + i] = pool->node_id_pool[src_off + i];
    }

    if (tid == 0) {
        out_counts[op] = count;
        out_keys[op]   = s_key;
    }
    // Note: the leaf's node_id_pool slots are NOT reclaimed here.
    // Pool is pre-allocated; reclamation can be done in a separate compaction
    // pass if needed, or the pool is simply sized large enough.
}

// ---------------------------------------------------------------------------
// KERNEL: bp_insert_kernel
//
// Each thread block inserts one (key, node_id) pair into the tree.
// "Inserting" means:
//   1. Traverse the tree from root to the correct leaf (greatest-lower-bound).
//   2. Lock the leaf, append the node_id, update the leaf key if needed.
//   3. If the leaf is full, set a "needs split" flag and let the caller
//      launch bp_split_kernel for that leaf.
//
// Inputs:
//   in_keys[op]     : float distance of the node to insert
//   in_node_ids[op] : graph node ID to insert
//
// Outputs:
//   out_full_leaves[op] : pool index of leaf that became full (-1 if not full)
// ---------------------------------------------------------------------------
__global__ void bp_insert_kernel(
    BPPool*        pool,
    int32_t        num_ops,
    const float*   in_keys,
    const int32_t* in_node_ids,
    int32_t*       out_full_leaves   // [num_ops], -1 if no split needed
)
{
    int op  = blockIdx.x;
    int tid = threadIdx.x;
    if (op >= num_ops) return;

    float   key     = in_keys[op];
    int32_t node_id = in_node_ids[op];

    extern __shared__ int32_t smem[]; // T int32_ts for parallel search

    __shared__ int32_t s_cur;
    __shared__ int32_t s_full_leaf;

    if (tid == 0) {
        s_cur       = pool->root;
        s_full_leaf = BP_NULL_IDX;
    }
    __syncthreads();

    // --- Step 1: traverse from root to leaf ---
    // All threads participate in parallel key search at each level.
    while (true) {
        int32_t cur_idx = s_cur;
        if (cur_idx == BP_NULL_IDX) break;

        BPNode& cur = pool->nodes[cur_idx];

        if (bp_is_leaf(cur)) break; // reached leaf level

        // Parallel search for child index
        int32_t child_i = bp_find_child_parallel(pool, cur, key, smem);
        // child_i is the index into cur's children array
        if (tid == 0) {
            s_cur = bp_child(pool, cur, child_i);
        }
        __syncthreads();
    }

    // --- Step 2: lock the leaf and insert ---
    if (tid == 0) {
        int32_t leaf_idx = s_cur;
        if (leaf_idx == BP_NULL_IDX) {
            // printf("leaf_idx == BP_NULL_IDX\n");
            out_full_leaves[op] = BP_NULL_IDX;
            return;
        }

        BPNode& leaf = pool->nodes[leaf_idx];

        // Spin-lock the leaf
        bp_lock(&leaf);

        // Append node_id
        if (leaf.count < leaf.capacity) {
            // printf("Appending...\n");
            int32_t pos = leaf.count;
            pool->node_id_pool[leaf.node_id_offset + pos] = node_id;
            leaf.count = pos + 1;
        }
        // else { printf("Leaf full!\n"); }

        // Update leaf key: it holds the minimum distance of all nodes in block.
        // The B+ tree is keyed on this minimum; inserting a smaller key
        // means we need to update it (and propagate up — see note below).
        float cur_key = bp_leaf_key(pool, leaf);
        if (key < cur_key) {
            bp_set_leaf_key(pool, leaf, key);
            // NOTE: key decrease propagation into parent separators is handled
            // lazily — the parent separator is an upper bound (GLB search still
            // works correctly even with stale separators as long as the actual
            // leaf key is authoritative).  A background fix-up pass can be
            // added if exact separator correctness is required.
        }

        // Even if we couldn't fit our item, signal that this leaf is full
        if (leaf.count >= leaf.capacity) {
            s_full_leaf = leaf_idx;
        }

        bp_unlock(&leaf);
        out_full_leaves[op] = s_full_leaf;
    }
}

// ---------------------------------------------------------------------------
// KERNEL: bp_split_kernel
//
// Each thread block splits one full leaf into two.
// Steps:
//   1. Lock the full leaf.
//   2. Allocate a new leaf node from the pool (thread 0).
//   3. Cooperatively copy the upper half of node_ids to the new leaf.
//   4. Update counts and keys.
//   5. Splice new leaf into the linked list.
//   6. Insert the new separator key into the parent internal node
//      (which may itself overflow — caller must check and re-split upward).
//
// Inputs:
//   in_leaf_indices[op]  : pool index of the leaf to split
//
// Outputs:
//   out_parent_full[op]  : pool index of parent if it became full (-1 otherwise)
// ---------------------------------------------------------------------------
__global__ void bp_split_kernel(
    BPPool*        pool,
    int32_t        num_ops,
    const int32_t* in_leaf_indices,
    int32_t*       out_parent_full   // [num_ops]
)
{
    int op  = blockIdx.x;
    int tid = threadIdx.x;
    int T   = blockDim.x;
    if (op >= num_ops) return;

    int32_t leaf_idx = in_leaf_indices[op];
    if (leaf_idx == BP_NULL_IDX) {
        if (tid == 0) out_parent_full[op] = BP_NULL_IDX;
        return;
    }

    extern __shared__ int32_t smem[];
    // smem layout: [0..T-1] = search scratch
    //              [T]      = new_leaf_idx
    //              [T+1]    = parent_idx
    //              [T+2]    = parent_full

    __shared__ int32_t s_new_leaf;
    __shared__ int32_t s_parent_full;
    __shared__ int32_t s_mid;       // split point

    // --- Step 1: allocate new leaf and compute split point ---
    if (tid == 0) {
        BPNode& leaf = pool->nodes[leaf_idx];
        bp_lock(&leaf);

        int32_t cap  = leaf.capacity;
        int32_t mid  = cap / 2; // lower half: [0, mid), upper half: [mid, cap)
        s_mid        = mid;

        // Allocate new leaf
        int32_t new_idx = bp_alloc_node(pool);
        bp_init_leaf(pool, new_idx, cap, leaf.parent);
        s_new_leaf = new_idx;

        // New leaf's node_id slice was allocated by bp_init_leaf.
        // It already has node_id_offset set.
        // Count for new leaf = cap - mid
        pool->nodes[new_idx].count = cap - mid;
        // Lower leaf keeps [0, mid)
        leaf.count = mid;
    }
    __syncthreads();

    BPNode& leaf     = pool->nodes[leaf_idx];
    BPNode& new_leaf = pool->nodes[s_new_leaf];
    int32_t mid      = s_mid;
    int32_t upper    = leaf.capacity - mid;

    // --- Step 2: cooperatively copy upper half to new leaf ---
    // Simultaneously find the minimum key of the upper half.
    for (int i = tid; i < upper; i += T) {
        int32_t nid = pool->node_id_pool[leaf.node_id_offset + mid + i];
        pool->node_id_pool[new_leaf.node_id_offset + i] = nid;
        // We don't store per-node distances in the leaf — the leaf key is
        // the block minimum.  The caller must provide the new key separately.
        // Here we copy IDs only; key update is done by the caller after
        // re-evaluating distances, OR we can reuse the existing split key
        // as the separator (the new leaf's key will be updated on next insert).
        // For correctness in GLB search, we set new_leaf key = old leaf key
        // (conservative: all nodes in both halves have dist >= old leaf key).
        (void)nid;
    }
    __syncthreads();

    // --- Step 3: finalize leaf keys and link list ---
    if (tid == 0) {
        // New leaf key = same as original (conservative; will be tightened
        // on subsequent inserts/distance updates).
        float orig_key = bp_leaf_key(pool, leaf);
        bp_set_leaf_key(pool, new_leaf, orig_key);

        // Splice into linked list: leaf <-> new_leaf <-> leaf.next_leaf
        new_leaf.prev_leaf = leaf_idx;
        new_leaf.next_leaf = leaf.next_leaf;
        if (leaf.next_leaf != BP_NULL_IDX) {
            BPNode& nxt = pool->nodes[leaf.next_leaf];
            bp_lock(&nxt);
            nxt.prev_leaf = s_new_leaf;
            bp_unlock(&nxt);
        }
        leaf.next_leaf = s_new_leaf;

        bp_unlock(&leaf);

        // --- Step 4: insert separator into parent ---
        int32_t parent_idx = leaf.parent;
        s_parent_full = BP_NULL_IDX;

        if (parent_idx == BP_NULL_IDX) {
            // Splitting the root leaf: create a new internal root
            int32_t root_idx = bp_alloc_node(pool);
            // Internal node capacity = same as leaf capacity (heuristic)
            bp_init_internal(pool, root_idx, leaf.capacity, BP_NULL_IDX);
            BPNode& root = pool->nodes[root_idx];

            // Root has 1 separator key and 2 children
            bp_set_sep_key(pool, root, 0, orig_key); // separator = old leaf key
            bp_set_child(pool, root, 0, leaf_idx);
            bp_set_child(pool, root, 1, s_new_leaf);
            root.count = 1;

            leaf.parent     = root_idx;
            new_leaf.parent = root_idx;

            atomicExch(&pool->root, root_idx);
        } else {
            // Insert separator into existing parent
            BPNode& parent = pool->nodes[parent_idx];
            bp_lock(&parent);

            // Find insertion position for orig_key in parent's sep keys
            int32_t pos = 0;
            while (pos < parent.count &&
                   bp_sep_key(pool, parent, pos) <= orig_key) pos++;

            // Shift keys and children right to make room
            for (int32_t j = parent.count; j > pos; j--) {
                bp_set_sep_key(pool, parent, j,
                               bp_sep_key(pool, parent, j - 1));
                bp_set_child(pool, parent, j + 1,
                             bp_child(pool, parent, j));
            }
            bp_set_sep_key(pool, parent, pos, orig_key);
            bp_set_child(pool, parent, pos + 1, s_new_leaf);
            new_leaf.parent = parent_idx;
            parent.count++;

            if (parent.count >= parent.capacity) {
                s_parent_full = parent_idx;
            }
            bp_unlock(&parent);
        }
    }
    __syncthreads();

    if (tid == 0) out_parent_full[op] = s_parent_full;
}

// ---------------------------------------------------------------------------
// KERNEL: bp_split_internal_kernel
//
// Splits a full internal node.  Same idea as bp_split_kernel but for
// internal nodes.  Called iteratively by the host when split propagates up.
// Single-threaded (internal nodes are small relative to leaf blocks).
// ---------------------------------------------------------------------------
__global__ void bp_split_internal_kernel(
    BPPool*        pool,
    int32_t        num_ops,
    const int32_t* in_node_indices,
    int32_t*       out_parent_full
)
{
    int op = blockIdx.x;
    if (op >= num_ops) return;
    if (threadIdx.x != 0) return; // single thread

    int32_t node_idx = in_node_indices[op];
    if (node_idx == BP_NULL_IDX) {
        out_parent_full[op] = BP_NULL_IDX;
        return;
    }

    BPNode& node = pool->nodes[node_idx];
    bp_lock(&node);

    int32_t cap = node.capacity;
    int32_t mid = cap / 2;

    // Allocate sibling internal node
    int32_t sib_idx = bp_alloc_node(pool);
    bp_init_internal(pool, sib_idx, cap, node.parent);
    BPNode& sib = pool->nodes[sib_idx];

    // The median key is promoted to parent; right half stays in sib
    float median_key = bp_sep_key(pool, node, mid);

    // Copy upper half of keys (excluding median) to sib
    int32_t sib_count = cap - mid - 1;
    for (int32_t i = 0; i < sib_count; i++) {
        bp_set_sep_key(pool, sib, i, bp_sep_key(pool, node, mid + 1 + i));
    }
    // Copy upper children to sib
    for (int32_t i = 0; i <= sib_count; i++) {
        int32_t child_i = bp_child(pool, node, mid + 1 + i);
        bp_set_child(pool, sib, i, child_i);
        // Update child's parent pointer
        pool->nodes[child_i].parent = sib_idx;
    }
    sib.count  = sib_count;
    node.count = mid; // lower half keeps [0, mid)

    bp_unlock(&node);

    // Insert median_key into parent
    int32_t parent_idx = node.parent;
    out_parent_full[op] = BP_NULL_IDX;

    if (parent_idx == BP_NULL_IDX) {
        // node was the root; create new root
        int32_t root_idx = bp_alloc_node(pool);
        bp_init_internal(pool, root_idx, cap, BP_NULL_IDX);
        BPNode& root = pool->nodes[root_idx];

        bp_set_sep_key(pool, root, 0, median_key);
        bp_set_child(pool, root, 0, node_idx);
        bp_set_child(pool, root, 1, sib_idx);
        root.count = 1;

        node.parent = root_idx;
        sib.parent  = root_idx;
        atomicExch(&pool->root, root_idx);
    } else {
        BPNode& parent = pool->nodes[parent_idx];
        bp_lock(&parent);

        int32_t pos = 0;
        while (pos < parent.count &&
               bp_sep_key(pool, parent, pos) <= median_key) pos++;

        for (int32_t j = parent.count; j > pos; j--) {
            bp_set_sep_key(pool, parent, j, bp_sep_key(pool, parent, j - 1));
            bp_set_child(pool, parent, j + 1, bp_child(pool, parent, j));
        }
        bp_set_sep_key(pool, parent, pos, median_key);
        bp_set_child(pool, parent, pos + 1, sib_idx);
        sib.parent = parent_idx;
        parent.count++;

        if (parent.count >= parent.capacity) {
            out_parent_full[op] = parent_idx;
        }
        bp_unlock(&parent);
    }
}
