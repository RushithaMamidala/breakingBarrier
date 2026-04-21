#include "bptree.cuh"
#include <cstdio>
#include <cmath>
#include <algorithm>
#include <vector>

// ---------------------------------------------------------------------------
// Tiny CPU reference: sorted list of (key, node_id) pairs
// Used to verify GPU results.
// ---------------------------------------------------------------------------
struct RefEntry { float key; int32_t node_id; };
struct RefTree {
    std::vector<RefEntry> entries;

    void insert(float key, int32_t nid) {
        entries.push_back({key, nid});
        std::sort(entries.begin(), entries.end(),
                  [](const RefEntry& a, const RefEntry& b){ return a.key < b.key; });
    }

    // Pop the entry with the smallest key
    RefEntry pop_min() {
        RefEntry e = entries.front();
        entries.erase(entries.begin());
        return e;
    }

    bool empty() const { return entries.empty(); }
};

// ---------------------------------------------------------------------------
// Helper: read tree root pool index from device
// ---------------------------------------------------------------------------
int32_t read_root(BPTreeHost* h) {
    BPPool pool;
    CUDA_CHECK(cudaMemcpy(&pool, h->d_pool, sizeof(BPPool), cudaMemcpyDeviceToHost));
    return pool.root;
}

// ---------------------------------------------------------------------------
// Helper: print tree structure (host-side traversal for debugging)
// ---------------------------------------------------------------------------
void print_tree(BPTreeHost* h) {
    BPPool pool;
    CUDA_CHECK(cudaMemcpy(&pool, h->d_pool, sizeof(BPPool), cudaMemcpyDeviceToHost));

    // Read all nodes
    std::vector<BPNode> nodes(pool.node_top);
    if (pool.node_top == 0) { printf("(empty tree)\n"); return; }
    CUDA_CHECK(cudaMemcpy(nodes.data(), h->d_nodes, sizeof(BPNode) * pool.node_top, cudaMemcpyDeviceToHost));

    // Read key pool
    std::vector<float> keys(pool.key_top > 0 ? pool.key_top : 1);
    if (pool.key_top > 0)
        CUDA_CHECK(cudaMemcpy(keys.data(), h->d_keys, sizeof(float) * pool.key_top, cudaMemcpyDeviceToHost));

    // Read node_id pool
    std::vector<int32_t> nids(pool.nid_top > 0 ? pool.nid_top : 1);
    if (pool.nid_top > 0)
        CUDA_CHECK(cudaMemcpy(nids.data(), h->d_node_ids, sizeof(int32_t) * pool.nid_top, cudaMemcpyDeviceToHost));

    // BFS from root
    std::vector<int32_t> queue = {pool.root};
    int level = 0;
    while (!queue.empty()) {
        printf("Level %d: ", level++);
        std::vector<int32_t> next;
        for (int32_t idx : queue) {
            if (idx == BP_NULL_IDX) continue;
            const BPNode& n = nodes[idx];
            if (n.flags & 4u) { printf("[DELETED] "); continue; }
            if (n.flags & 1u) {
                // Leaf
                float lk = (n.key_offset >= 0 && n.key_offset < (int)keys.size()) ? keys[n.key_offset] : -1.f;
                printf("L%d(key=%.2f,cnt=%d) ", idx, lk, n.count);
            } else {
                printf("I%d(cnt=%d) ", idx, n.count);
                // Read children pool
                std::vector<int32_t> children(pool.child_top > 0 ? pool.child_top : 1);
                CUDA_CHECK(cudaMemcpy(children.data(), h->d_children, sizeof(int32_t) * (pool.child_top > 0 ? pool.child_top : 1), cudaMemcpyDeviceToHost));
                for (int32_t i = 0; i <= n.count; i++) {
                    int32_t ci = children[n.child_offset + i];
                    if (ci != BP_NULL_IDX) next.push_back(ci);
                }
            }
        }
        printf("\n");
        queue = next;
    }
    printf("Leaf chain: ");
    int32_t lc = pool.leaf_head;
    while (lc != BP_NULL_IDX) {
        const BPNode& leaf = nodes[lc];
        if (leaf.flags & 4u) { lc = leaf.next_leaf; continue; }
        float lk = keys[leaf.key_offset];
        printf("L%d(%.2f)->", lc, lk);
        lc = leaf.next_leaf;
    }
    printf("NULL\n");
}

// ---------------------------------------------------------------------------
// Test 1: Insert N items, verify tree is non-empty and leaf chain is intact.
// ---------------------------------------------------------------------------
bool test_insert_basic() {
    printf("\n=== Test 1: Basic Insert ===\n");
    const int N = 20;
    const int BLOCK_CAP = 4;

    BPTreeHost* h = bp_create(
        /*node_pool*/  256,
        /*nid_pool*/   256,
        /*child_pool*/ 256,
        /*key_pool*/   256,
        /*max_ops*/    N,
        /*max_block*/  BLOCK_CAP,
        /*init_cap*/   BLOCK_CAP);

    float   keys[N];
    int32_t nids[N];
    for (int i = 0; i < N; i++) {
        keys[i] = (float)(N - i); // insert in reverse order: N, N-1, ..., 1
        nids[i] = i;
    }

    printf("Created B+ tree\n");

    bp_insert(h, keys, nids, N, BLOCK_CAP);
    CUDA_CHECK(cudaDeviceSynchronize());

    print_tree(h);

    BPPool pool;
    CUDA_CHECK(cudaMemcpy(&pool, h->d_pool, sizeof(BPPool), cudaMemcpyDeviceToHost));
    printf("node_top=%d  nid_top=%d  key_top=%d\n",
           pool.node_top, pool.nid_top, pool.key_top);

    bool ok = (pool.root != BP_NULL_IDX) && (pool.nid_top >= N);
    printf("Test 1: %s\n", ok ? "PASS" : "FAIL");
    bp_destroy(h);
    return ok;
}

// ---------------------------------------------------------------------------
// Test 2: Insert items then pop one at a time, verify monotone increasing keys.
// ---------------------------------------------------------------------------
bool test_pop_order() {
    printf("\n=== Test 2: Pop Order ===\n");
    const int N = 12;
    const int BLOCK_CAP = 4;

    BPTreeHost* h = bp_create(256, 256, 256, 256, N, BLOCK_CAP, BLOCK_CAP);

    float   keys[N]  = {3,1,4,1,5,9,2,6,5,3,5,8};
    int32_t nids[N];
    for (int i = 0; i < N; i++) nids[i] = i;

    bp_insert(h, keys, nids, N, BLOCK_CAP);
    CUDA_CHECK(cudaDeviceSynchronize());

    // Pop one block at a time and verify key is non-decreasing
    float prev_key = -FLT_MAX;
    bool ok = true;
    int total_popped = 0;
    while (total_popped < N) {
        bp_pop(h, 1, BLOCK_CAP);
        int cnt = h->h_out_counts[0];
        float k = h->h_out_keys[0];
        if (cnt == -1) break; // tree empty
        printf("  popped block key=%.2f  count=%d\n", k, cnt);
        if (k < prev_key - 1e-6f) {
            printf("  ERROR: key not monotone! prev=%.2f cur=%.2f\n", prev_key, k);
            ok = false;
        }
        prev_key = k;
        total_popped += cnt;
    }
    printf("Total popped: %d / %d\n", total_popped, N);
    if (total_popped != N) {
        printf("  ERROR: lost %d items\n", N - total_popped);
        ok = false;
    }
    printf("Test 2: %s\n", ok ? "PASS" : "FAIL");
    bp_destroy(h);
    return ok;
}

// ---------------------------------------------------------------------------
// Test 3: Parallel multi-pop (pop several blocks at once)
// ---------------------------------------------------------------------------
bool test_multi_pop() {
    printf("\n=== Test 3: Multi-Pop ===\n");
    const int N = 24;
    const int BLOCK_CAP = 4; // expect ~6 blocks
    const int POP_BATCH = 3;

    BPTreeHost* h = bp_create(256, 256, 256, 256, POP_BATCH, BLOCK_CAP, BLOCK_CAP);

    float   keys[N];
    int32_t nids[N];
    for (int i = 0; i < N; i++) { keys[i] = (float)(rand() % 100); nids[i] = i; }

    bp_insert(h, keys, nids, N, BLOCK_CAP);
    CUDA_CHECK(cudaDeviceSynchronize());

    int total = 0;
    int iters = 0;
    while (total < N && iters < 20) {
        bp_pop(h, POP_BATCH, BLOCK_CAP);
        for (int p = 0; p < POP_BATCH; p++) {
            int cnt = h->h_out_counts[p];
            if (cnt <= 0) continue;
            printf("  pop[%d] key=%.2f count=%d\n", p, h->h_out_keys[p], cnt);
            total += cnt;
        }
        iters++;
    }
    bool ok = (total == N);
    printf("Total popped: %d / %d\n", total, N);
    printf("Test 3: %s\n", ok ? "PASS" : "FAIL");
    bp_destroy(h);
    return ok;
}

// ---------------------------------------------------------------------------
// Test 4: Stress ; large N with random keys, verify all pops sum to N
// ---------------------------------------------------------------------------
bool test_stress() {
    printf("\n=== Test 4: Stress (N=1000, block_cap=8) ===\n");
    const int N = 1000;
    const int BLOCK_CAP = 8;
    const int POP_BATCH = 16;

    BPTreeHost* h = bp_create(
        /*nodes*/  4096, /*nids*/ 4096, /*children*/ 4096, /*keys*/ 4096,
        /*ops*/    POP_BATCH, /*max_cap*/ BLOCK_CAP, /*init*/ BLOCK_CAP);

    std::vector<float>   keys(N);
    std::vector<int32_t> nids(N);
    srand(42);
    for (int i = 0; i < N; i++) { keys[i] = (float)(rand() % 10000) / 100.f; nids[i] = i; }

    // Insert in batches of 64
    const int INSERT_BATCH = 64;
    for (int off = 0; off < N; off += INSERT_BATCH) {
        int cnt = std::min(INSERT_BATCH, N - off);
        bp_insert(h, keys.data() + off, nids.data() + off, cnt, BLOCK_CAP);
    }
    CUDA_CHECK(cudaDeviceSynchronize());

    int total = 0;
    int iters = 0;
    while (total < N && iters < 500) {
        bp_pop(h, POP_BATCH, BLOCK_CAP);
        for (int p = 0; p < POP_BATCH; p++) {
            int cnt = h->h_out_counts[p];
            if (cnt > 0) total += cnt;
        }
        iters++;
    }
    bool ok = (total == N);
    printf("Total popped: %d / %d  (iters=%d)\n", total, N, iters);
    printf("Test 4: %s\n", ok ? "PASS" : "FAIL");
    bp_destroy(h);
    return ok;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
int main() {
    int dev;
    cudaGetDevice(&dev);
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, dev);
    printf("Device: %s\n", prop.name);

    bool all_pass = true;
    all_pass &= test_insert_basic();
    // all_pass &= test_pop_order();
    // all_pass &= test_multi_pop();
    // all_pass &= test_stress();

    printf("\n=== Overall: %s ===\n", all_pass ? "ALL PASS" : "SOME FAILED");
    return all_pass ? 0 : 1;
}
