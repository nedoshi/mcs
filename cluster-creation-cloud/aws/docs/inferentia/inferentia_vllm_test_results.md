 # LLM Inference on AWS Inferentia2: Performance Benchmarking & Analysis

## Table of Contents
- [Deployment Configuration](#deployment-configuration)
- [Dense Model Comparative Benchmarks (Run 3)](#dense-model-comparative-benchmarks-run-3)
- [Container & Model Weight Architecture](#container--model-weight-architecture)
- [Storage Options Comparison: EBS vs EFS vs S3](#storage-options-comparison-ebs-vs-efs-vs-s3)
- [NeuronCore Utilization Analysis](#neuroncore-utilization-analysis)
- [Benchmarking Methodology](#benchmarking-methodology)
- [Key Performance Metrics Explained](#key-performance-metrics-explained)
- [Benchmark Test Configurations](#benchmark-test-configurations)
- [Results](#results)
- [Throughput & Capacity Analysis](#throughput--capacity-analysis)
- [Capacity Planning: 100 Developers](#capacity-planning-100-developers)
- [Total Cost of Ownership (TCO)](#total-cost-of-ownership-tco)
- [Conclusions & Recommendations](#conclusions--recommendations)
- [Appendix: Raw GuideLLM Test Results](#appendix-raw-guidellm-test-results)

---

## Deployment Configuration

### Run 2: inf2.48xlarge (Current)

| Parameter | Value |
|---|---|
| **Model** | Qwen3-Coder-30B-A3B-Instruct (MoE: 30.5B total, 3.3B active/token) |
| **Platform** | Red Hat OpenShift Service on AWS (ROSA) HCP 4.21.6 |
| **Instance** | inf2.48xlarge (24 NeuronCores, 384 GB HBM, 192 vCPUs, 768 GB RAM) |
| **Accelerator** | AWS Inferentia2 (12 Inferentia2 chips, 24 NeuronCores) |
| **Serving Engine** | vLLM 0.13.0 with Neuron SDK 2.28.0 |
| **Container Image** | `public.ecr.aws/neuron/pytorch-inference-vllm-neuronx:0.13.0-neuronx-py312-sdk2.28.0-ubuntu24.04` (19.0 GB) |
| **Framework** | neuronx-distributed-inference |
| **Tensor Parallel** | tp_degree=16 (hidden_size 2048 / 16 = 128 elements per shard) |
| **MoE Config** | moe_tp_degree=2, moe_ep_degree=8 (128 experts, 8 active/token) |
| **Max Model Length** | 16,384 tokens |
| **Max Concurrent Seqs** | 16 (batch_size=16) |
| **Neuron Cores Used** | 16 of 24 (NEURON_RT_VISIBLE_CORES=0-15) |
| **Scheduler** | neuron-scheduler (topology-aware contiguous core allocation) |
| **Storage** | EBS gp3 PVC, 500 Gi (model weights + NEFF cache on same volume) |
| **NEFF Cache Location** | `/mnt/models/neuron-cache` on PVC (persistent across restarts) |
| **Endpoint** | OpenAI-compatible API (vLLM `/v1/completions`, `/v1/chat/completions`) |

### Run 1: inf2.24xlarge (Previous)

| Parameter | Value |
|---|---|
| **Model** | Qwen3-Coder-30B-A3B-Instruct (MoE: 30.5B total, 3.3B active/token) |
| **Platform** | Red Hat OpenShift Service on AWS (ROSA) HCP 4.21.6 |
| **Instance** | inf2.24xlarge (12 NeuronCores, 192 GB HBM, 96 vCPUs, 384 GB RAM) |
| **Accelerator** | AWS Inferentia2 (6 Inferentia2 chips, 12 NeuronCores) |
| **Serving Engine** | vLLM 0.13.0 with Neuron SDK 2.28.0 |
| **Framework** | neuronx-distributed-inference |
| **Tensor Parallel** | tp_degree=8 (hidden_size 2048 must be evenly divisible) |
| **MoE Config** | moe_tp_degree=1, moe_ep_degree=8 (128 experts, 8 active/token) |
| **Max Model Length** | 8,192 tokens |
| **Max Concurrent Seqs** | 16 (batch_size=16) |
| **Neuron Cores Used** | 8 of 12 (NEURON_RT_VISIBLE_CORES=0-7) |
| **Storage** | EBS gp3 PVC, 500 Gi (model weights + NEFF cache on same volume) |
| **NEFF Cache Location** | `/mnt/models/neuron-cache` on PVC (persistent across restarts) |
| **Endpoint** | OpenAI-compatible API (vLLM `/v1/completions`, `/v1/chat/completions`) |

### Run 3: Dense Model Comparison on inf2.24xlarge

Two dense coding models were tested in parallel on separate inf2.24xlarge nodes:

**Node A — Qwen3-32B**

| Parameter | Value |
|---|---|
| **Model** | Qwen/Qwen3-32B (Dense, 32.8B parameters) |
| **Platform** | Red Hat OpenShift Service on AWS (ROSA) HCP 4.21.6 |
| **Instance** | inf2.24xlarge (12 NeuronCores, 192 GB HBM, 96 vCPUs, 384 GB RAM) |
| **Serving Engine** | vLLM 0.13.0 with Neuron SDK 2.28.0 |
| **Framework** | neuronx-distributed-inference |
| **Tensor Parallel** | tp_degree=8 (hidden_size 5120 / 8 = 640 elements per shard) |
| **Max Model Length** | 4,096 tokens |
| **Max Concurrent Seqs** | 4 |
| **BF16 Weight Size** | ~64 GB |
| **Neuron Cores Used** | 8 of 12 (NEURON_RT_VISIBLE_CORES=0-7) |
| **Storage** | EBS gp3 PVC, 200 Gi (model weights + NEFF cache on same volume) |
| **NEFF Cache Location** | `/models/neuron-cache` on PVC (persistent across restarts) |

**Node B — CodeLlama-34B-Instruct**

| Parameter | Value |
|---|---|
| **Model** | codellama/CodeLlama-34b-Instruct-hf (Dense, 33.7B parameters) |
| **Platform** | Red Hat OpenShift Service on AWS (ROSA) HCP 4.21.6 |
| **Instance** | inf2.24xlarge (12 NeuronCores, 192 GB HBM, 96 vCPUs, 384 GB RAM) |
| **Serving Engine** | vLLM 0.13.0 with Neuron SDK 2.28.0 |
| **Framework** | neuronx-distributed-inference |
| **Tensor Parallel** | tp_degree=8 (hidden_size 8192 / 8 = 1024 elements per shard) |
| **Max Model Length** | 4,096 tokens |
| **Max Concurrent Seqs** | 4 |
| **BF16 Weight Size** | ~68 GB |
| **Neuron Cores Used** | 8 of 12 (NEURON_RT_VISIBLE_CORES=0-7) |
| **Storage** | EBS gp3 PVC, 200 Gi (model weights + NEFF cache on same volume) |
| **NEFF Cache Location** | `/models/neuron-cache` on PVC (persistent across restarts) |

---

## Dense Model Comparative Benchmarks (Run 3)

### Benchmark Methodology

Both models were tested simultaneously on separate inf2.24xlarge nodes using GuideLLM 0.5.4. Three tests per model:

| Test | Prompt Tokens | Output Tokens | Rate Type | Duration |
|------|---------------|---------------|-----------|----------|
| Small | 128 | 128 | Synchronous (1 req at a time) | 120s |
| Medium | 512 | 512 | Synchronous (1 req at a time) | 120s |
| Throughput | 2048 | 1024 | Constant @ 0.5 req/s | 180s |

### Head-to-Head Results

#### Test 1: Small Workload (128 in / 128 out, Synchronous)

| Metric | Qwen3-32B | CodeLlama-34B | Winner |
|--------|-----------|---------------|--------|
| **TTFT (mdn)** | 1,091 ms | 1,185 ms | Qwen3-32B |
| **TTFT (p95)** | 1,103 ms | 1,248 ms | Qwen3-32B |
| **ITL (mdn)** | 37.8 ms | 42.2 ms | Qwen3-32B |
| **ITL (p95)** | 38.3 ms | 43.4 ms | Qwen3-32B |
| **TPOT (mdn)** | 46.1 ms | 51.2 ms | Qwen3-32B |
| **Gen tokens/s (mean)** | 21.9 | 19.7 | Qwen3-32B |
| **Total tokens/s (mean)** | 45.1 | 40.4 | Qwen3-32B |
| **Completed Requests** | 21 | 19 | Qwen3-32B |

#### Test 2: Medium Workload (512 in / 512 out, Synchronous)

| Metric | Qwen3-32B | CodeLlama-34B | Winner |
|--------|-----------|---------------|--------|
| **TTFT (mdn)** | 1,111 ms | 1,203 ms | Qwen3-32B |
| **TTFT (p95)** | 1,139 ms | 1,211 ms | Qwen3-32B |
| **ITL (mdn)** | 37.8 ms | 42.2 ms | Qwen3-32B |
| **ITL (p95)** | 38.1 ms | 42.8 ms | Qwen3-32B |
| **TPOT (mdn)** | 39.9 ms | 44.5 ms | Qwen3-32B |
| **Gen tokens/s (mean)** | 25.2 | 22.6 | Qwen3-32B |
| **Total tokens/s (mean)** | 50.9 | 45.5 | Qwen3-32B |
| **Completed Requests** | 6 | 6 | Tie |

#### Test 3: Throughput Workload (2048 in / 1024 out, Constant @ 0.5 req/s)

| Metric | Qwen3-32B | CodeLlama-34B | Winner |
|--------|-----------|---------------|--------|
| **TTFT (mdn)** | 36,360 ms | 41,489 ms | Qwen3-32B |
| **TTFT (p95)** | 59,980 ms | 59,816 ms | CodeLlama-34B |
| **ITL (mdn)** | 41.2 ms | 46.0 ms | Qwen3-32B |
| **ITL (p95)** | 42.2 ms | 47.1 ms | Qwen3-32B |
| **TPOT (mdn)** | 76.7 ms | 86.5 ms | Qwen3-32B |
| **Gen tokens/s (mean)** | 92.2 | 83.5 | Qwen3-32B |
| **Total tokens/s (mean)** | 1,134.7 | 1,114.7 | Qwen3-32B |
| **Concurrency (mdn)** | 33.0 | 34.0 | Tie |
| **Completed Requests** | 12 | 12 | Tie |

### Key Findings

1. **Qwen3-32B consistently outperforms CodeLlama-34B-Instruct** across all metrics on Inferentia2, winning every latency and throughput comparison.

2. **Inter-token latency (ITL)** is remarkably consistent for both models:
   - Qwen3-32B: 37.8–41.2 ms across all workloads
   - CodeLlama-34B: 42.2–46.0 ms across all workloads
   - This ~10% ITL advantage for Qwen3-32B translates to faster real-time streaming.

3. **Time to first token (TTFT)** is comparable for small/medium workloads (~1.1s for both) but explodes under load (Test 3) because requests queue while the single-threaded Neuron prefill processes earlier requests.

4. **Both models compile and run reliably on inf2.24xlarge with tp=8**, using 8 of 12 NeuronCores (33% waste). Key compilation workarounds:
   - Qwen3-32B requires NxD framework with `fused_qkv: false` and all NKI kernels disabled to avoid HLO tracing errors.
   - CodeLlama-34B requires NxD framework with `enable_bucketing: false` and NKI kernels disabled to avoid Neuron compiler internal errors on context encoding buckets.

5. **inf2.24xlarge is the right instance size** for these ~32–34B dense models. 192 GB HBM provides ample room for 64–68 GB weights plus KV cache.

### Compilation Notes

| Model | HLO Generation | Compilation | Total Cold Start |
|-------|---------------|-------------|-----------------|
| Qwen3-32B | 8 seconds | ~6 minutes | ~8 minutes |
| CodeLlama-34B | 45 seconds | ~12 minutes | ~15 minutes |

Both models required disabling NKI kernel optimizations (`qkv_kernel_enabled: false`, `attn_kernel_enabled: false`) and bucketing (`enable_bucketing: false`) to compile successfully on Neuron SDK 2.28.0. These issues are expected to be resolved in future SDK versions.

---

## Container & Model Weight Architecture

### Component Sizes

| Component | Size | Storage Type | Notes |
|---|---|---|---|
| **vLLM Runtime Container** | 19.0 GB | ECR → CRI-O image cache on node | Pull time: ~2 min on first schedule |
| **Qwen3-Coder-30B-A3B weights** (MoE) | 57 GB | EBS PVC (gp3, RWO) | BF16, 30.5B total params |
| **Qwen3-32B weights** (Dense) | 64 GB | EBS PVC (gp3, RWO) | BF16, 32.8B params |
| **CodeLlama-34B-Instruct weights** (Dense) | 68 GB | EBS PVC (gp3, RWO) | BF16, 33.7B params |
| **Neuron compilation cache (NEFF)** | 20–40 GB per model | EBS PVC (same volume) | Specific to model + tp_degree + max_model_len + SDK version |
| **Typical per-node EBS footprint** | ~100–120 GB used / 200 GB provisioned | EBS gp3 | One model + one NEFF cache per node |

### Model Weight Decoupling

Model weights are **decoupled from the container image**. The 19 GB runtime image contains only the vLLM engine, PyTorch, and Neuron SDK. Model files are loaded at startup from a PersistentVolumeClaim mounted at `/mnt/models` (or `/models`). This decoupling means:

- The container image is model-agnostic and reusable across all supported models.
- Model weights can be updated, swapped, or versioned independently of the serving runtime.
- The Neuron compilation cache (`NEURON_COMPILE_CACHE_URL`) is stored on the same or a separate writable volume, enabling warm restarts without recompilation.

---

## Storage Options Comparison: EBS vs EFS vs S3

### Why Storage Choice Matters for Inferentia2

Unlike GPU-based inference where models load directly from disk into GPU memory, Inferentia2 requires a **Neuron compilation step** on first startup. The compiler reads model weights, generates HLO intermediate representations, compiles them into NEFF binaries, and writes the compiled artifacts to a cache directory. This process has specific storage requirements:

1. **Model weights** must be readable at startup (~57–68 GB for 30B+ models).
2. **NEFF cache** must be writable during compilation (~20–40 GB per model configuration).
3. **Subsequent restarts** with the same config skip compilation if the NEFF cache is available (cold start drops from 20–55 min to 2–5 min).

### Observed Data from Testing

| Metric | Observed Value | Source |
|---|---|---|
| Qwen3-32B NEFF compilation time | ~6 min (after 8s HLO generation) | Run 3, inf2.24xlarge |
| CodeLlama-34B NEFF compilation time | ~12 min (after 45s HLO generation) | Run 3, inf2.24xlarge |
| Qwen3-Coder-30B-A3B compilation time | ~15–20 min | Run 1/2, inf2.24xlarge/48xlarge |
| Model download time (HuggingFace → PVC) | ~8–12 min for 57–68 GB | All runs |
| Warm restart (cached NEFFs on EBS) | ~2–5 min | All runs |
| S3 download overhead (KServe init container) | ~60–90 sec for 8 GB model | Appendix D, Lesson #5 |
| S3 download estimate for 64 GB model | ~5–8 min (same-region, multi-part) | Extrapolated |

### Three-Way Comparison

| Dimension | EBS gp3 (PVC, RWO) | EFS Standard (PVC, RWX) | S3 Standard |
|---|---|---|---|
| **Cost per 100 GB/month** | **$8.00** | $30.00 (3.75× EBS) | **$2.30** (cheapest) |
| **Access mode** | ReadWriteOnce | **ReadWriteMany** | **ReadWriteMany** (via Mountpoint CSI or init container) |
| **Sequential read throughput** | 125 MiB/s baseline (provisionable to 1,000 MiB/s) | Elastic: scales with load; ~100–500 MiB/s typical | **100+ Gbps** with multi-part parallel reads |
| **Write support** | **Full POSIX** (random + sequential) | **Full POSIX** (random + sequential) | No random writes; append-only via Mountpoint; S3 API only |
| **Read latency (first byte)** | **<1 ms** (block device) | 1–5 ms (NFS over network) | 5–20 ms (HTTP GET, first byte) |
| **Neuron NEFF cache writable?** | **Yes** — ideal for compilation | **Yes** — works but higher latency during write-heavy compilation | **No** — Mountpoint is append-only; cannot write NEFF cache directly |
| **Multi-node model sharing** | No — one pod per volume | **Yes** — multiple pods across nodes | **Yes** — any number of pods |
| **Cold start (no NEFF cache)** | Model already on disk → compile only (6–20 min) | Model already on PVC → compile only (6–20 min, slightly slower I/O) | Download model (5–8 min) + compile (6–20 min) = **11–28 min** |
| **Warm restart (NEFF cached)** | **2–5 min** (fastest — model + cache on local block device) | 3–7 min (model on NFS, cache on emptyDir) | Download model (5–8 min) + load cache (2–3 min) = **7–11 min** |
| **Pre-allocation required?** | Yes — provision volume size upfront | No — pay for stored bytes only | No — pay for stored bytes only |
| **Operational complexity** | **Low** — standard Kubernetes PVC | Medium — EFS filesystem + mount targets + CSI driver setup | Medium — S3 bucket + IAM/IRSA + Mountpoint CSI or init container |
| **KServe compatibility** | Limited — KServe mounts PVCs read-only | Works with `storageUri: pvc://` (read-only mount OK if NEFF cache on emptyDir) | **Best** — KServe natively supports `storageUri: s3://` |
| **Disaster recovery** | Snapshots (manual or automated) | Cross-AZ replication built-in | **11 nines durability**, versioning, cross-region replication |

### Cost Scenario: Production with 4 Models on 4 Nodes

Assumes 4 dense models (~65 GB average weights), each with a ~30 GB NEFF cache, on 4 `inf2.24xlarge` nodes.

| Storage Strategy | Model Weights | NEFF Cache | Total Stored | Monthly Cost |
|---|---|---|---|---|
| **EBS only** (one 200 GB PVC per node) | 4 × 65 GB = 260 GB on EBS | 4 × 30 GB = 120 GB on EBS | 4 × 200 GB = 800 GB EBS | **$64.00** |
| **EFS only** (shared RWX PVC) | 260 GB on EFS | 120 GB on emptyDir (lost on restart) | 260 GB EFS | **$78.00** + recompilation on every restart |
| **S3 only** (KServe with storageUri) | 260 GB on S3 | 120 GB on emptyDir (lost on restart) | 260 GB S3 | **$5.98** + re-download + recompilation on every restart |
| **Hybrid: S3 + EBS** (recommended) | 260 GB on S3 (source of truth) + local emptyDir | 4 × 30 GB = 120 GB on EBS (persistent per node) | 260 GB S3 + 120 GB EBS | **$15.58** ($5.98 S3 + $9.60 EBS) |
| **Hybrid: S3 + EBS (pre-compiled)** | 260 GB on S3 | 120 GB on S3 (pre-compiled NEFF) + EBS local copy | 380 GB S3 + 120 GB EBS | **$18.34** ($8.74 S3 + $9.60 EBS) — fastest startup |

### Storage Cost vs Project Cost: Why Performance Wins

Before choosing a storage strategy, it is critical to compare storage cost against total project cost:

| Deployment (3yr reserved) | Monthly Project Cost | EBS Only (best perf.) | Hybrid S3+EBS | EFS Only | Storage as % of Project |
|---|---|---|---|---|---|
| **Single inf2.24xlarge** | $6,186/mo | $16/mo | $16/mo | $30/mo | **0.16–0.48%** |
| **Option A: 4× inf2.24xlarge** | $20,945/mo | $64/mo | $16/mo | $78/mo | **0.07–0.37%** |
| **Option B: 3× inf2.48xlarge** | $30,807/mo | $64/mo | $16/mo | $78/mo | **0.05–0.25%** |

The maximum storage cost difference between the cheapest option (hybrid S3+EBS at $16/mo) and the most expensive option (EFS at $78/mo) is **$62/month** — less than **0.30%** of the total project cost. Optimizing for storage cost savings of $48/month while accepting slower restarts and higher operational complexity against a $20,000+/month infrastructure bill is the wrong trade-off.

**The correct strategy is to optimize for performance and simplicity, not storage cost.**

### EBS gp3 IOPS and Latency Analysis

#### What EBS gp3 Delivers

| Metric | gp3 Baseline (included) | gp3 Provisioned (max) | Additional Cost |
|---|---|---|---|
| **IOPS** | 3,000 | 16,000 | $0.005/IOPS/mo ($65/mo for max) |
| **Throughput** | 125 MiB/s | 1,000 MiB/s | $0.04/MiB/s/mo ($35/mo for max) |
| **Latency** | <1 ms (single-digit microseconds for cached reads) | Same | N/A |
| **Access pattern** | Full POSIX — sequential, random, read, write | Same | N/A |

#### What Inferentia2 + vLLM Actually Needs

| I/O Phase | Access Pattern | Duration | IOPS Demand | Throughput Demand |
|---|---|---|---|---|
| **Model loading** (startup) | Sequential read, 57–68 GB | 2–9 min depending on throughput | Low (~100–500 sequential) | **High** — throughput-bound |
| **NEFF compilation** (first startup) | Mixed read/write, many small files + large NEFFs | 6–20 min | Moderate (~500–2,000) | Moderate (50–100 MiB/s) |
| **NEFF cache read** (warm restart) | Sequential read, 20–40 GB | 1–3 min | Low | Moderate (100–125 MiB/s) |
| **Inference serving** (steady state) | **None** — all data in NeuronCore HBM | Continuous | **Zero** | **Zero** |

Key insight: once the model and NEFF cache are loaded into NeuronCore HBM, the storage volume sees **zero I/O during inference**. Storage performance only matters during startup and compilation — a one-time event per pod lifecycle.

#### Baseline gp3 vs Provisioned gp3

| Scenario | gp3 Baseline (free) | gp3 + Provisioned Throughput | Impact |
|---|---|---|---|
| **Model load (68 GB)** | 68 GB / 125 MiB/s ≈ **9 min** | 68 GB / 1,000 MiB/s ≈ **1.1 min** | 8 min faster cold start |
| **NEFF cache read (30 GB)** | 30 GB / 125 MiB/s ≈ **4 min** | 30 GB / 1,000 MiB/s ≈ **30 sec** | 3.5 min faster warm restart |
| **NEFF compilation** | CPU-bound (3,000 IOPS sufficient) | No improvement | N/A |
| **Inference serving** | Zero I/O | Zero I/O | No impact |
| **Additional cost (per node)** | $0 | $35/mo (1,000 MiB/s) | $140/mo for 4 nodes |

Provisioning 1,000 MiB/s throughput on gp3 costs $35/node/month ($140 total for 4 nodes). This represents **0.67%** of the Option A project cost but cuts warm restart from ~5 min to ~1.5 min and cold start from ~12 min to ~4 min. This is worth it for production deployments where node replacement or pod rescheduling latency matters.

### Recommendation

**Best overall: EBS gp3 per node (with provisioned throughput for production)**

| Use Case | Recommended Storage | IOPS / Throughput | Monthly Storage Cost | Rationale |
|---|---|---|---|---|
| **Development / testing** | EBS gp3, 200 GB per node (baseline) | 3,000 IOPS / 125 MiB/s | $16/node | Simplest setup. Baseline throughput is sufficient — compilation is CPU-bound, not I/O-bound. Fastest warm restart (2–5 min). Zero operational complexity. |
| **Production** | EBS gp3, 200 GB per node (provisioned throughput) | 3,000 IOPS / **1,000 MiB/s** | $51/node | Provisioned throughput cuts model load from 9 min to 1 min and warm restart from 5 min to 1.5 min. At $35/node/month extra (<0.2% of project cost), the startup time improvement is worth it. |
| **Backup / model registry** | S3 (in addition to EBS) | N/A | $6/mo for 260 GB | S3 as a durable backup for model weights and pre-compiled NEFF cache. Not for serving — only for disaster recovery and model versioning. Download to EBS at pod startup via init container if the PVC is empty. |

**Why EBS gp3 wins over the hybrid approach:**

1. **Fastest restart**: 2–5 min warm (baseline) or 1–2 min (provisioned throughput). No S3 download step.
2. **Zero runtime I/O**: Once loaded, inference runs entirely in NeuronCore HBM. Storage performance during serving is irrelevant.
3. **Full POSIX writes**: The Neuron compiler needs random-write access for NEFF artifacts. EBS provides this natively. S3 Mountpoint and S3 API cannot.
4. **Compilation cache persistence**: NEFF cache survives pod restarts on EBS. S3-only and EFS-with-emptyDir approaches lose the cache and require 6–20 min recompilation.
5. **Cost is irrelevant**: $64/month (4 nodes × $16) is 0.31% of the $20,945/month project cost. Even with provisioned throughput ($204/month total), storage is under 1%.
6. **Simplest operations**: No S3 buckets, IAM roles, IRSA configuration, init containers, or CSI drivers beyond the default EBS CSI. Standard Kubernetes PVC.

**When to add S3 (as backup, not primary):**

- Store model weights and pre-compiled NEFF artifacts in S3 as a disaster recovery source. If a node is replaced and its EBS volume is lost, an init container can pull from S3 to a fresh PVC.
- S3 versioning provides an audit trail of model and NEFF versions. EBS snapshots can serve the same purpose but with less flexibility.
- This is an operational convenience, not a cost optimization. The S3 cost ($6/month) is negligible.

**Why not EFS?** At $0.30/GB/month, EFS costs 3.75× more than EBS and adds 1–5 ms latency per I/O operation. Its only advantage — ReadWriteMany — is unnecessary because each Inferentia node runs its own model with its own NEFF cache. There is no benefit to sharing volumes across nodes. EFS also loses the NEFF cache on pod restart (stored on emptyDir), forcing 6–20 min recompilation.

**Why not S3 as primary storage?** S3 cannot host the NEFF compilation cache (no POSIX random writes). Using S3 as the primary model source adds a 5–8 min download step on every pod restart. With EBS, the model is already on disk — restart is immediate.

### KServe Integration: Single PVC with Read-Write Annotation (Validated 2026-04-01)

**Recommended approach for RHOAI 3.3+ (KServe 0.14+):** Use a **single EBS gp3 PVC per node** mounted read-write via the `storage.kserve.io/readonly: "false"` annotation on the `InferenceService`. The Neuron compiler writes NEFF cache to a subdirectory (`/mnt/models/neuron-cache`) on the same PVC.

| PVC | Purpose | Size | Access | Monthly Cost |
|-----|---------|------|--------|-------------|
| **model-storage-pvc** | Model weights + NEFF compilation cache | 200 GB | Read-write | **$16** |

**Why single PVC?** KServe v0.14+ ([PR #3885](https://github.com/kserve/kserve/pull/3885)) introduced the `storage.kserve.io/readonly: "false"` annotation, which overrides the default read-only PVC mount. RHOAI 3.3 bundles KServe 0.15, which includes this feature. This eliminates the need for a separate NEFF cache PVC while retaining all benefits:

- **Model weights + NEFF cache on one PVC** — simplest architecture, one PVC to manage
- **NEFF cache persists across restarts** — warm restart in ~9 min (baseline) or ~3-4 min (provisioned throughput)
- **KServe-native** — model visible in OpenShift AI dashboard, supports traffic management

**Validation (2026-04-01):** The single-PVC approach was validated on the cluster:

| Test | Result |
|------|--------|
| PVC mounted read-write by KServe | **PASS** — `ReadOnly: false` confirmed on pod spec |
| NEFF cache written to PVC | **PASS** — NEFF artifacts written to `/mnt/models/neuron-cache/` |
| Neuron scheduler propagated | **PASS** — `schedulerName: neuron-scheduler` on underlying Deployment |
| Autoscaling disabled | **PASS** — `serving.kserve.io/autoscalerClass: none` working correctly |
| Model serving via KServe | **PASS** — InferenceService became Ready, inference working |

**Legacy: Dual-PVC Architecture (Phase 1b, 2026-03-31):** For pre-RHOAI 3.3 deployments (KServe < 0.14), a dual-PVC approach was validated: model weights on a read-only PVC + NEFF cache on a separate read-write PVC. This adds $4/node/month but works with any KServe version.

See [vLLM on Inferentia2 — KServe Deployment](vllmoninferentia.md#section-3-serving-models-with-kserve-on-inferentia2) for full deployment steps.

---

## NeuronCore Utilization Analysis

### Why Not All NeuronCores Are Usable

The `inf2.48xlarge` has **24 NeuronCores** (12 Inferentia2 chips × 2 cores each), but only **16 cores** are used for this model. The `inf2.24xlarge` has **12 NeuronCores** but only **8** are used. This is a fundamental constraint of **tensor parallelism divisibility**.

### The Constraint

Tensor parallelism (TP) shards model weight matrices across NeuronCores. The `tp_degree` must **evenly divide** the model's `hidden_size`, `num_attention_heads`, and `num_key_value_heads`. For Qwen3-Coder-30B-A3B-Instruct:

| Model Dimension | Value |
|---|---|
| `hidden_size` | 2048 |
| `num_attention_heads` | 16 |
| `num_key_value_heads` | 4 |
| `num_experts` | 128 |
| `num_experts_per_tok` | 8 |

### Divisibility Check Against Available Core Counts

| tp_degree | 2048 / tp | 16 / tp | 4 / tp | Valid? | Notes |
|---|---|---|---|---|---|
| **24** | 85.33 | 0.67 | 0.17 | **No** | Cannot use all cores on inf2.48xlarge |
| **16** | 128 | 1 | 0.25 | **Yes** | KV heads replicated via GQA (4 heads → 4 replicas per TP group) |
| **12** | 170.67 | 1.33 | 0.33 | **No** | Cannot use all cores on inf2.24xlarge |
| **8** | 256 | 2 | 0.5 | **Yes** | KV heads replicated via GQA (4 heads → 2 replicas per TP group) |
| **4** | 512 | 4 | 1 | **Yes** | Clean division on all dimensions |
| **2** | 1024 | 8 | 2 | **Yes** | Minimal parallelism |

The TP degree must be a **power of 2** to divide the model's hidden dimensions (which are themselves powers of 2 in virtually all modern LLMs). Since 24 and 12 are not powers of 2, neither `inf2.48xlarge` (24 cores) nor `inf2.24xlarge` (12 cores) can use all their NeuronCores with this model.

### MoE Expert Parallelism (EP) Doesn't Help

The MoE layers add expert parallelism (`moe_ep_degree`) as another sharding axis. The total NeuronCores used equals `moe_tp_degree × moe_ep_degree`. For Qwen3-Coder with 128 experts and 8 active per token:

| Configuration | moe_tp × moe_ep | Total Cores | Fits 24? | Fits 12? |
|---|---|---|---|---|
| tp=2, ep=8 | 2 × 8 = 16 | 16 | No (8 idle) | No (too many) |
| tp=4, ep=8 | 4 × 8 = 32 | 32 | No (exceeds) | No (exceeds) |
| tp=1, ep=8 | 1 × 8 = 8 | 8 | No (16 idle) | No (4 idle) |
| tp=2, ep=12 | 2 × 12 = 24 | 24 | **Yes** | No |
| tp=1, ep=12 | 1 × 12 = 12 | 12 | No | **Yes** |

In theory, `moe_ep_degree=12` could use all 24 cores on `inf2.48xlarge`, but:
- The EP degree must evenly divide the number of experts: 128 / 12 = 10.67 — **not an integer**
- Valid EP degrees for 128 experts: 1, 2, 4, 8, 16, 32, 64, 128 (powers of 2)
- So the MoE architecture of this model also prevents using 12 or 24 cores

### Resource Waste by Instance Type

| Instance | Total Cores | Max Usable (tp_degree) | Idle Cores | Waste % | On-Demand $/hr |
|---|---|---|---|---|---|
| **inf2.xlarge** | 2 | 2 (tp=2) | 0 | 0% | $0.76 |
| **inf2.8xlarge** | 2 | 2 (tp=2) | 0 | 0% | $1.97 |
| **inf2.24xlarge** | 12 | 8 (tp=8) | 4 | 33% | $6.49 |
| **inf2.48xlarge** | 24 | 16 (tp=16) | 8 | 33% | $12.98 |

Both the 12-core and 24-core Inferentia2 instances waste exactly 33% of their NeuronCores for this model.

### Effective Cost Per Usable Core

| Instance | Total Cores | Usable Cores | $/hr (OD) | $/hr per Usable Core |
|---|---|---|---|---|
| inf2.xlarge | 2 | 2 | $0.76 | $0.380 |
| inf2.8xlarge | 2 | 2 | $1.97 | $0.985 |
| inf2.24xlarge | 12 | 8 | $6.49 | $0.811 |
| inf2.48xlarge | 24 | 16 | $12.98 | $0.811 |

The `inf2.24xlarge` and `inf2.48xlarge` have identical per-usable-core cost ($0.811/hr), so the choice between them depends on whether you need `tp=16` (for higher context length and throughput) or `tp=8` is sufficient.

### Strategies to Reclaim Idle Cores

| Strategy | Description | Feasibility |
|---|---|---|
| **Co-locate a second model** | Run a smaller model (e.g., embedding, routing, or code completion) on idle cores using `NEURON_RT_VISIBLE_CORES=16-23` | **High** — requires a second vLLM deployment with separate core range |
| **Use a model with compatible dimensions** | Choose a model where `hidden_size % 24 = 0` (e.g., hidden_size=3072 or 4608) | **Medium** — limited model choices |
| **Use inf2.xlarge/8xlarge instances** | Zero waste (2 cores, tp=2), but only viable for very small models | **Low** — insufficient for 30B parameter models |
| **Wait for Trainium2** | Trn2.48xlarge has 32 NeuronCores (power of 2), eliminating the waste for tp=16 or tp=32 | **Future** — depends on Trn2 vLLM support maturity |

### Comparison with Trainium for This Model

| Instance | Chip | Cores | tp=16 Usable | tp=32 Usable | Waste (tp=16) | $/hr (OD) |
|---|---|---|---|---|---|---|
| inf2.48xlarge | Inferentia2 | 24 | 16 (67%) | N/A | 33% | $12.98 |
| trn1.32xlarge | Trainium v1 | 32 | 16 (50%) | 32 (100%) | 0-50% | $21.50 |
| trn2.48xlarge | Trainium v2 | 32 | 16 (50%) | 32 (100%) | 0-50% | ~$17.79 |

Trainium instances have 32 cores (a power of 2), which enables tp=32 with zero waste. However, tp=32 requires `num_key_value_heads` (4) to be replicated 8× per core group, increasing memory bandwidth pressure. The cost-per-usable-core comparison favors Inferentia2 at tp=16 ($0.811 vs $1.11-$1.34/core), but Trainium can use all cores at tp=32 if the model's GQA replication overhead is acceptable.

---

## Benchmarking Methodology

### GuideLLM

[GuideLLM](https://github.com/neuralmagic/guidellm) (v0.5.4) is Red Hat's open-source LLM benchmarking toolkit for evaluating inference deployments under production-like conditions. Install with `pip install guidellm` (requires Python 3.10+). It connects to any OpenAI-compatible endpoint and measures TTFT, inter-token latency (ITL), end-to-end latency, output token throughput, and request throughput across configurable load patterns (synchronous, constant rate, Poisson, sweep). Sweep mode automatically profiles the full performance envelope from idle to saturation.

### How to Reproduce These Tests

```bash
guidellm benchmark run \
  --target <VLLM_ENDPOINT_URL> \
  --model "Qwen3-Coder-30B-A3B-Instruct" \
  --rate-type sweep \
  --max-seconds 30 \
  --data "prompt_tokens=<N>,output_tokens=<M>" \
  --output-path "./bench_<N>in_<M>out.json"
```

| Parameter | Purpose |
|---|---|
| `--target` | OpenAI-compatible vLLM endpoint URL |
| `--rate-type sweep` | 10-point sweep: synchronous → max throughput |
| `--max-seconds 30` | Duration per rate point (use 90 for >512 output tokens) |
| `--data "prompt_tokens=N,output_tokens=M"` | Synthetic prompt/output token sizes |

---

## Key Performance Metrics Explained

### Latency Metrics (User Experience)

| Metric | What It Measures | Why It Matters |
|---|---|---|
| **TTFT** (Time to First Token) | Delay before the user sees the first word | Critical for interactive UX — users perceive <500ms as "instant" |
| **TPOT / ITL** (Time Per Output Token) | Time between each generated token | Determines perceived streaming speed; <50ms feels real-time |
| **E2E Latency** | Total time to complete a response | Sets the upper bound for request timeouts and SLAs |

### Throughput Metrics (System Capacity)

| Metric | What It Measures | Why It Matters |
|---|---|---|
| **Output Tokens/sec** | Total tokens generated per second across all requests | Primary capacity metric — directly translates to cost efficiency |
| **Requests/sec** | Completed requests per second | Determines how many users can be served concurrently |
| **Tokens per Dollar** | Tokens generated per unit cost | Business metric for comparing accelerator/instance options |

### Quality Metrics (Model Accuracy)

| Metric | What It Measures | Why It Matters |
|---|---|---|
| **Perplexity** | Model's uncertainty about next token | Lower = more confident predictions; benchmark against CPU/GPU baseline |
| **Pass@k** (for code models) | Probability of correct code in k attempts | Standard metric for code generation quality (HumanEval, MBPP) |
| **Accuracy / F1** | Task-specific correctness | Validates that quantization or compilation hasn't degraded quality |

> **Note**: GuideLLM focuses on **inference performance** metrics (latency + throughput). For quality evaluation, use complementary tools like `lm-eval-harness` or `bigcode-evaluation-harness`.

---

## Benchmark Test Configurations

Six configurations were tested to cover a range of real-world usage patterns:

| Test # | Prompt Tokens | Output Tokens | Total Tokens | Use Case |
|---|---|---|---|---|
| 1 | 128 | 128 | 256 | Quick completions, autocomplete |
| 2 | 128 | 256 | 384 | Short prompt, medium response |
| 3 | 256 | 256 | 512 | Balanced medium workload |
| 4 | 512 | 512 | 1,024 | Code generation, explanations |
| 5 | 1,024 | 512 | 1,536 | Large context code review |
| 6 | 2,048 | 1,024 | 3,072 | Large document analysis |

### Commands Used

**Test 1: Small (128 in / 128 out)**
```bash
guidellm benchmark run \
  --target https://vllm-qwen3-coder-llm-serving.apps.rosa.<CLUSTER_NAME>.<CLUSTER_HASH>.openshiftapps.com \
  --model "Qwen3-Coder-30B-A3B-Instruct" \
  --rate-type sweep \
  --max-seconds 30 \
  --data "prompt_tokens=128,output_tokens=128" \
  --output-path "./bench_128in_128out.json"
```

**Test 2: Short prompt / Medium response (128 in / 256 out)**
```bash
guidellm benchmark run \
  --target https://vllm-qwen3-coder-llm-serving.apps.rosa.<CLUSTER_NAME>.<CLUSTER_HASH>.openshiftapps.com \
  --model "Qwen3-Coder-30B-A3B-Instruct" \
  --rate-type sweep \
  --max-seconds 30 \
  --data "prompt_tokens=128,output_tokens=256" \
  --output-path "./bench_128in_256out.json"
```

**Test 3: Balanced medium (256 in / 256 out)**
```bash
guidellm benchmark run \
  --target https://vllm-qwen3-coder-llm-serving.apps.rosa.<CLUSTER_NAME>.<CLUSTER_HASH>.openshiftapps.com \
  --model "Qwen3-Coder-30B-A3B-Instruct" \
  --rate-type sweep \
  --max-seconds 30 \
  --data "prompt_tokens=256,output_tokens=256" \
  --output-path "./bench_256in_256out.json"
```

**Test 4: Code generation (512 in / 512 out)**
```bash
guidellm benchmark run \
  --target https://vllm-qwen3-coder-llm-serving.apps.rosa.<CLUSTER_NAME>.<CLUSTER_HASH>.openshiftapps.com \
  --model "Qwen3-Coder-30B-A3B-Instruct" \
  --rate-type sweep \
  --max-seconds 30 \
  --data "prompt_tokens=512,output_tokens=512" \
  --output-path "./bench_512in_512out.json"
```

**Test 5: Large context code review (1024 in / 512 out)**
```bash
guidellm benchmark run \
  --target https://vllm-qwen3-coder-llm-serving.apps.rosa.<CLUSTER_NAME>.<CLUSTER_HASH>.openshiftapps.com \
  --model "Qwen3-Coder-30B-A3B-Instruct" \
  --rate-type sweep \
  --max-seconds 30 \
  --data "prompt_tokens=1024,output_tokens=512" \
  --output-path "./bench_1024in_512out.json"
```

**Test 6: Large document analysis (2048 in / 1024 out)**
```bash
guidellm benchmark run \
  --target https://vllm-qwen3-coder-llm-serving.apps.rosa.<CLUSTER_NAME>.<CLUSTER_HASH>.openshiftapps.com \
  --model "Qwen3-Coder-30B-A3B-Instruct" \
  --rate-type sweep \
  --max-seconds 90 \
  --backend-args '{"timeout": 120.0}' \
  --data "prompt_tokens=2048,output_tokens=1024" \
  --output-path "./bench_2048in_1024out.json"
```

> **Note on Test 6**: The default `--max-seconds 30` is too short for 1024 output tokens (~43s at 24 tok/s synchronous). Use `--max-seconds 90` and `--backend-args '{"timeout": 120.0}'` for large token configurations.

---

## Results

### Run 2: inf2.48xlarge (tp=16, 16 NeuronCores) — GuideLLM Sweep Results

Each test runs a 10-point sweep: 1 synchronous, 1 max-throughput, and 8 constant rate points with increasing concurrency. All benchmarks run inside the cluster (pod-to-service, no TLS overhead). Model context length: 16,384 tokens.

#### Test 1: 128 prompt / 128 output tokens

**Latency (Completed Requests)**

| Strategy | Req Latency (Mdn/p95) | TTFT Mdn/p95 (ms) | ITL Mdn/p95 (ms) | TPOT Mdn/p95 (ms) |
|---|---|---|---|---|
| synchronous | 5.6s / 5.7s | 632 / 633 | 39.3 / 39.7 | 43.9 / 44.3 |
| throughput | 29.2s / 43.7s | 19,978 / 37,547 | 76.9 / 109.8 | 227.7 / 341.7 |
| constant (low) | 6.3s / 6.5s | 656 / 666 | 44.7 / 45.6 | 49.5 / 50.4 |
| constant (mid) | 9.1s / 9.4s | 672 / 681 | 66.3 / 68.7 | 71.1 / 73.4 |
| constant (high) | 15.3s / 15.5s | 662 / 910 | 115.4 / 115.5 | 119.6 / 120.9 |

**Throughput (All Requests)**

| Strategy | Concurrency (Mdn) | Output tok/s (Mean) | Completed Reqs |
|---|---|---|---|
| synchronous | 1 | 23.2 | 6 |
| throughput | 32 | 142.5 | 48 |
| constant (low) | 2 | 33.1 | 8 |
| constant (mid) | 5 | 60.7 | 14 |
| constant (high) | 9 | 72.9 | 17 |

#### Test 2: 128 prompt / 256 output tokens

**Latency (Completed Requests)**

| Strategy | Req Latency (Mdn/p95) | TTFT Mdn/p95 (ms) | ITL Mdn/p95 (ms) | TPOT Mdn/p95 (ms) |
|---|---|---|---|---|
| synchronous | 10.6s / 10.7s | 632 / 632 | 39.3 / 39.3 | 41.6 / 41.6 |
| throughput | 19.7s / 39.3s | 9,575 / 28,678 | 56.1 / 74.4 | 76.9 / 153.5 |
| constant (low) | 11.4s / 11.5s | 649 / 674 | 42.3 / 42.3 | 44.7 / 44.8 |
| constant (mid) | 12.7s / 12.7s | 660 / 675 | 47.1 / 47.3 | 49.6 / 49.8 |
| constant (high) | 15.9s / 16.2s | 662 / 680 | 59.9 / 60.7 | 62.2 / 63.1 |

**Throughput (All Requests)**

| Strategy | Concurrency (Mdn) | Output tok/s (Mean) | Completed Reqs |
|---|---|---|---|
| synchronous | 1 | 24.5 | 3 |
| throughput | 32 | 211.8 | 32 |
| constant (low) | 1 | 28.6 | 3 |
| constant (mid) | 3 | 53.3 | 6 |
| constant (high) | 4 | 71.4 | 8 |

#### Test 3: 256 prompt / 256 output tokens

**Latency (Completed Requests)**

| Strategy | Req Latency (Mdn/p95) | TTFT Mdn/p95 (ms) | ITL Mdn/p95 (ms) | TPOT Mdn/p95 (ms) |
|---|---|---|---|---|
| synchronous | 10.7s / 10.8s | 632 / 633 | 39.4 / 39.9 | 41.7 / 42.2 |
| throughput | 19.6s / 39.3s | 9,573 / 28,612 | 55.9 / 74.6 | 76.7 / 153.5 |
| constant (low) | 11.4s / 11.4s | 656 / 673 | 42.0 / 42.0 | 44.4 / 44.4 |
| constant (mid) | 12.7s / 12.7s | 664 / 683 | 47.1 / 47.3 | 49.6 / 49.7 |
| constant (high) | 15.9s / 16.1s | 664 / 680 | 59.8 / 60.6 | 62.2 / 62.9 |

**Throughput (All Requests)**

| Strategy | Concurrency (Mdn) | Output tok/s (Mean) | Completed Reqs |
|---|---|---|---|
| synchronous | 1 | 24.4 | 3 |
| throughput | 32 | 211.8 | 32 |
| constant (low) | 1 | 28.7 | 3 |
| constant (mid) | 3 | 53.4 | 6 |
| constant (high) | 4 | 71.5 | 8 |

#### Test 4: 512 prompt / 512 output tokens

**Latency (Completed Requests)**

| Strategy | Req Latency (Mdn/p95) | TTFT Mdn/p95 (ms) | ITL Mdn/p95 (ms) | TPOT Mdn/p95 (ms) |
|---|---|---|---|---|
| synchronous | 20.7s / 20.7s | 609 / 632 | 39.3 / 39.4 | 40.4 / 40.5 |
| throughput | 29.7s / 59.5s | 9,576 / 38,700 | 47.8 / 56.9 | 58.0 / 116.3 |
| constant (low) | 22.0s / 22.0s | 617 / 617 | 41.9 / 41.9 | 43.0 / 43.0 |
| constant (mid) | 24.0s / 24.1s | 614 / 646 | 45.8 / 45.9 | 46.9 / 47.1 |
| constant (high) | 29.0s / 29.2s | 608 / 658 | 55.5 / 55.8 | 56.6 / 57.0 |

**Throughput (All Requests)**

| Strategy | Concurrency (Mdn) | Output tok/s (Mean) | Completed Reqs |
|---|---|---|---|
| synchronous | 1 | 25.1 | 2 |
| throughput | 32 | 278.1 | 32 |
| constant (low) | 1 | 23.9 | 1 |
| constant (mid) | 2-3 | 36.0-49.4 | 2-3 |
| constant (high) | 2 | 33.4-35.3 | 2 |

#### Test 5: 1024 prompt / 512 output tokens

**Latency (Completed Requests)**

| Strategy | Req Latency (Mdn/p95) | TTFT Mdn/p95 (ms) | ITL Mdn/p95 (ms) | TPOT Mdn/p95 (ms) |
|---|---|---|---|---|
| synchronous | 20.7s / 20.9s | 611 / 632 | 39.3 / 39.8 | 40.5 / 40.9 |
| throughput | 29.7s / 59.4s | 9,580 / 38,628 | 47.7 / 56.8 | 57.9 / 116.0 |
| constant (low) | 22.1s / 22.1s | 620 / 620 | 42.0 / 42.0 | 43.2 / 43.2 |
| constant (mid) | 24.6s / 24.7s | 665 / 677 | 46.8 / 46.9 | 48.1 / 48.2 |
| constant (high) | 30.3s / 30.3s | 612 / 612 | 58.1 / 58.1 | 59.1 / 59.1 |

**Throughput (All Requests)**

| Strategy | Concurrency (Mdn) | Output tok/s (Mean) | Completed Reqs |
|---|---|---|---|
| synchronous | 1 | 25.0 | 2 |
| throughput | 32 | 278.7 | 32 |
| constant (low) | 1 | 23.8 | 1 |
| constant (mid) | 3 | 49.4-49.5 | 3 |
| constant (high) | 1-2 | 17.3-34.3 | 1-2 |

#### Test 6: 2048 prompt / 1024 output tokens

Test 6 is currently running. Results will be appended upon completion.

---

### Run 1: inf2.24xlarge (tp=8, 8 NeuronCores) — GuideLLM Sweep Results (Previous)

Each test runs a 10-point sweep with max_model_len=8,192 tokens.

#### Test 1: 128 prompt / 128 output tokens

**Latency (Completed Requests)**

| Strategy | Req Latency (Mdn/p95) | TTFT Mdn/p95 (ms) | ITL Mdn/p95 (ms) | TPOT Mdn/p95 (ms) |
|---|---|---|---|---|
| synchronous | 5.7s / 5.8s | 523 / 524 | 40.9 / 41.4 | 44.6 / 45.2 |
| throughput | 26.0s / 39.0s | 17,400 / 32,831 | 71.5 / 98.3 | 203.1 / 304.7 |
| constant (low) | 6.3s / 6.4s | 546 / 568 | 45.4 / 46.1 | 49.3 / 50.0 |
| constant (mid) | 8.0s / 8.1s | 555 / 571 | 58.8 / 59.2 | 62.5 / 63.2 |
| constant (high) | 12.2s / 12.2s | 567 / 575 | 91.5 / 91.6 | 95.2 / 95.3 |

**Throughput (All Requests)**

| Strategy | Concurrency (Mdn/Mean) | Output tok/s (Mdn/Mean) | Total tok/s (Mean) |
|---|---|---|---|
| synchronous | 1.0 / 1.0 | 24.5 / 22.7 | 46.8 |
| throughput | 512 / 508 | 119.6 / 159.4 | 1,975.9 |
| constant (low) | 2.0 / 1.7 | 43.4 / 34.9 | 74.5 |
| constant (mid) | 5.0 / 4.4 | 61.6 / 71.9 | 157.4 |
| constant (high) | 13.0 / 10.5 | 94.7 / 112.9 | 264.7 |

#### Test 2: 128 prompt / 256 output tokens

**Latency (Completed Requests)**

| Strategy | Req Latency (Mdn/p95) | TTFT Mdn/p95 (ms) | ITL Mdn/p95 (ms) | TPOT Mdn/p95 (ms) |
|---|---|---|---|---|
| synchronous | 10.9s / 11.0s | 524 / 524 | 40.9 / 40.9 | 42.7 / 42.8 |
| throughput | 18.2s / 36.6s | 7,792 / 25,530 | 54.6 / 69.5 | 71.2 / 142.8 |
| constant (low) | 11.5s / 11.5s | 542 / 550 | 43.0 / 43.1 | 44.9 / 45.1 |
| constant (mid) | 12.8s / 12.9s | 549 / 568 | 48.0 / 48.3 | 50.0 / 50.3 |
| constant (high) | 14.9s / 15.0s | 540 / 578 | 56.2 / 56.5 | 58.2 / 58.5 |

**Throughput (All Requests)**

| Strategy | Concurrency (Mdn/Mean) | Output tok/s (Mdn/Mean) | Total tok/s (Mean) |
|---|---|---|---|
| synchronous | 1.0 / 1.0 | 24.5 / 23.8 | 36.4 |
| throughput | 512 / 508 | 174.9 / 226.9 | 2,106.1 |
| constant (low) | 1.0 / 1.4 | 23.3 / 30.2 | 47.4 |
| constant (mid) | 4.0 / 3.2 | 55.6 / 65.8 | 107.2 |
| constant (high) | 8.0 / 6.2 | 84.8 / 108.8 | 186.9 |

#### Test 3: 256 prompt / 256 output tokens

**Latency (Completed Requests)**

| Strategy | Req Latency (Mdn/p95) | TTFT Mdn/p95 (ms) | ITL Mdn/p95 (ms) | TPOT Mdn/p95 (ms) |
|---|---|---|---|---|
| synchronous | 10.9s / 11.0s | 523 / 524 | 40.9 / 41.2 | 42.7 / 43.0 |
| throughput | 18.2s / 36.4s | 7,782 / 25,526 | 54.2 / 69.4 | 71.1 / 142.3 |
| constant (low) | 11.6s / 11.6s | 570 / 575 | 42.9 / 43.1 | 45.0 / 45.2 |
| constant (mid) | 12.7s / 12.8s | 549 / 572 | 47.4 / 47.8 | 49.4 / 49.8 |
| constant (high) | 14.9s / 14.9s | 538 / 567 | 56.2 / 56.4 | 58.1 / 58.4 |

**Throughput (All Requests)**

| Strategy | Concurrency (Mdn/Mean) | Output tok/s (Mdn/Mean) | Total tok/s (Mean) |
|---|---|---|---|
| synchronous | 1.0 / 1.0 | 24.5 / 23.7 | 48.2 |
| throughput | 512 / 507 | 175.5 / 227.6 | 3,990.7 |
| constant (low) | 1.0 / 1.4 | 23.3 / 30.2 | 63.7 |
| constant (mid) | 4.0 / 3.2 | 56.9 / 65.8 | 155.0 |
| constant (high) | 8.0 / 6.2 | 87.9 / 108.6 | 251.8 |

#### Test 4: 512 prompt / 512 output tokens

**Latency (Completed Requests)**

| Strategy | Req Latency (Mdn/p95) | TTFT Mdn/p95 (ms) | ITL Mdn/p95 (ms) | TPOT Mdn/p95 (ms) |
|---|---|---|---|---|
| synchronous | 21.5s / 21.6s | 495 / 523 | 41.0 / 41.3 | 41.9 / 42.1 |
| throughput | 28.9s / 57.7s | 7,778 / 36,226 | 48.0 / 55.2 | 56.5 / 112.6 |
| constant (low) | 22.4s / 22.4s | 501 / 501 | 42.9 / 42.9 | 43.8 / 43.8 |
| constant (mid) | 24.6s / 25.4s | 496 / 559 | 47.3 / 48.5 | 48.1 / 49.5 |
| constant (high) | 29.3s / 29.4s | 496 / 535 | 56.3 / 56.4 | 57.2 / 57.4 |

**Throughput (All Requests)**

| Strategy | Concurrency (Mdn/Mean) | Output tok/s (Mdn/Mean) | Total tok/s (Mean) |
|---|---|---|---|
| synchronous | 1.0 / 1.0 | 24.2 / 24.1 | 48.5 |
| throughput | 512 / 506 | 220.7 / 286.3 | 5,015.3 |
| constant (low) | 2.0 / 1.7 | 46.6 / 40.2 | 90.8 |
| constant (mid) | 5.0 / 4.5 | 75.8 / 97.7 | 247.2 |
| constant (high) | 8.0 / 8.5 | 95.1 / 154.2 | 441.6 |

#### Test 5: 1024 prompt / 512 output tokens

**Latency (Completed Requests)**

| Strategy | Req Latency (Mdn/p95) | TTFT Mdn/p95 (ms) | ITL Mdn/p95 (ms) | TPOT Mdn/p95 (ms) |
|---|---|---|---|---|
| synchronous | 21.4s / 21.5s | 497 / 523 | 40.9 / 41.0 | 41.7 / 42.0 |
| throughput | 28.7s / 57.3s | 7,775 / 35,960 | 47.5 / 55.1 | 56.0 / 112.0 |
| constant (low) | 22.6s / 22.6s | 505 / 505 | 43.2 / 43.2 | 44.1 / 44.1 |
| constant (mid) | 24.7s / 24.7s | 554 / 568 | 47.3 / 47.3 | 48.3 / 48.3 |
| constant (high) | 29.4s / 29.5s | 498 / 536 | 56.5 / 56.7 | 57.3 / 57.7 |

**Throughput (All Requests)**

| Strategy | Concurrency (Mdn/Mean) | Output tok/s (Mdn/Mean) | Total tok/s (Mean) |
|---|---|---|---|
| synchronous | 1.0 / 1.0 | 24.4 / 24.2 | 72.9 |
| throughput | 512 / 494 | 223.3 / 288.0 | 9,796.3 |
| constant (low) | 2.0 / 1.7 | 46.3 / 40.2 | 140.6 |
| constant (mid) | 5.0 / 4.5 | 73.8 / 98.1 | 395.0 |
| constant (high) | 8.0 / 8.5 | 92.6 / 154.1 | 721.8 |

#### Test 6: 2048 prompt / 1024 output tokens

**Latency (Completed Requests)**

| Strategy | Req Latency (Mdn/p95) | TTFT Mdn/p95 (ms) | ITL Mdn/p95 (ms) | TPOT Mdn/p95 (ms) |
|---|---|---|---|---|
| synchronous | 48.8s / 49.0s | 865 / 891 | 46.8 / 47.0 | 47.6 / 47.9 |
| throughput | 61.6s / 61.6s | 6,815 / 13,598 | 52.7 / 59.4 | 60.2 / 60.2 |
| constant (low) | 49.7s / 49.9s | 871 / 945 | 47.7 / 47.8 | 48.5 / 48.7 |
| constant (mid) | 52.6s / 52.7s | 928 / 938 | 50.5 / 50.6 | 51.4 / 51.4 |
| constant (high) | 58.0s / 58.2s | 922 / 946 | 55.8 / 55.9 | 56.6 / 56.8 |

**Throughput (All Requests)**

| Strategy | Concurrency (Mdn/Mean) | Output tok/s (Mdn/Mean) | Total tok/s (Mean) |
|---|---|---|---|
| synchronous | 1.0 / 1.0 | 21.3 / 21.1 | 63.6 |
| throughput | 512 / 497 | 207.2 / 266.3 | 9,331.7 |
| constant (low) | 1.0 / 1.4 | 21.4 / 29.0 | 95.2 |
| constant (mid) | 5.0 / 3.8 | 61.8 / 76.0 | 272.5 |
| constant (high) | 8.0 / 7.3 | 102.1 / 130.5 | 514.3 |

> **Key observation**: TTFT increased significantly to ~865-946ms (vs ~495-570ms for ≤1024 prompt tokens), reflecting the longer prefill time for 2048 input tokens. ITL also slightly increased to ~47ms (vs ~41ms), and single-user throughput dropped to ~21 tok/s (vs ~24 tok/s). This shows the impact of large context on Inferentia2 performance.

### Cross-Test Comparison Summary

| Test | Prompt/Output | TTFT (sync, ms) | ITL (sync, ms) | Single-user tok/s | Peak tok/s (const) | Peak Concurrency |
|---|---|---|---|---|---|---|
| 1 | 128 / 128 | 523 | 40.9 | 22.7 | 112.9 | ~10.5 |
| 2 | 128 / 256 | 524 | 40.9 | 23.8 | 108.8 | ~6.2 |
| 3 | 256 / 256 | 523 | 40.9 | 23.7 | 108.6 | ~6.2 |
| 4 | 512 / 512 | 495 | 41.0 | 24.1 | 154.2 | ~8.5 |
| 5 | 1024 / 512 | 497 | 40.9 | 24.2 | 154.1 | ~8.5 |
| 6 | 2048 / 1024 | 865 | 46.8 | 21.1 | 130.5 | ~7.3 |

---

## Throughput & Capacity Analysis

### Maximum Token Generation Capacity

Based on GuideLLM benchmark measurements:

| Parameter | Value | Source |
|---|---|---|
| Single-user output throughput | ~23-24 tokens/sec | GuideLLM synchronous mode |
| Single-user TTFT | ~523 ms | GuideLLM synchronous mode |
| Single-user ITL | ~41 ms | GuideLLM synchronous mode |
| Peak output throughput (realistic) | ~109-113 tokens/sec | GuideLLM constant rate (concurrency ~6-10) |
| Peak output throughput (max burst) | ~159-228 tokens/sec | GuideLLM throughput mode (512 concurrency, extreme latency) |
| Max concurrent sequences | 16 | vLLM config (batch_size=16) |
| Max model length | 8,192 tokens | vLLM deployment config |

### Daily Token Generation Estimate

**Scenario 1: Realistic sustained load** (based on GuideLLM sweep, ~110 output tokens/sec at concurrency ~6):

```
Output tokens per minute:   110 × 60         = 6,600 tokens/min
Output tokens per hour:     6,600 × 60       = 396,000 tokens/hr
Output tokens per day:      396,000 × 24     = 9,504,000 tokens/day (~9.5M tokens/day)
```

**Scenario 2: Conservative (50% utilization)** (~55 output tokens/sec average):

```
Output tokens per minute:   55 × 60          = 3,300 tokens/min
Output tokens per hour:     3,300 × 60       = 198,000 tokens/hr
Output tokens per day:      198,000 × 24     = 4,752,000 tokens/day (~4.8M tokens/day)
```

**Scenario 3: Single active developer** (~24 output tokens/sec):

```
Output tokens per minute:   24 × 60          = 1,440 tokens/min
Output tokens per hour:     1,440 × 60       = 86,400 tokens/hr
Output tokens per day:      86,400 × 24      = 2,073,600 tokens/day (~2.1M tokens/day)
```

### How to Calculate Max Tokens Per Day for Your Workload

Use this formula to estimate daily token capacity for your specific usage pattern:

```
Daily Output Tokens = Output_tok/s × Utilization_fraction × 86,400

Where:
  Output_tok/s = from the benchmark table at your expected concurrency level
  Utilization_fraction = fraction of the day the server is actively generating
    - 1.0 = 24/7 continuous generation (theoretical max)
    - 0.5 = active ~12 hours/day
    - 0.33 = active ~8 hours/day (typical business hours)
    - 0.1 = typical developer workload (sporadic prompts, ~2.4 hours active)
```

**Example**: Team of 4 developers during business hours (concurrency ~4, ~65 output tok/s):
```
65 × 0.33 × 86,400 = 1,852,200 output tokens/day (~1.9M tokens/day)
```

### Concurrent User Capacity

Based on GuideLLM measurements across all sweep tests (128-1024 output tokens):

| Concurrency | Output tok/s (aggregate) | Output tok/s (per user) | TTFT (ms) | TPOT (ms) | User Experience |
|---|---|---|---|---|---|
| 1 | ~24 | ~24 | ~495-523 | ~42-45 | Excellent — fluid streaming |
| 2 | ~35-47 | ~18-24 | ~501-570 | ~44-49 | Very good |
| 4 | ~60-80 | ~15-20 | ~496-559 | ~47-63 | Good — slight delay in streaming |
| 6 | ~77-115 | ~13-19 | ~541-556 | ~50-72 | Acceptable for code generation |
| 8 | ~88-154 | ~11-19 | ~495-553 | ~52-80 | Noticeable latency increase at small tokens; OK at large tokens |
| 10+ | ~103-154 | ~10-15 | ~496-567 | ~55-95 | Per-user speed depends on token config |
| 512 (burst) | ~159-288 | <1 | ~7,775-36,226 | ~56-305 | Unusable for interactive — batch only |

### Scaling Recommendations

| Scaling Option | Impact | Cost Factor |
|---|---|---|
| **Add replica** (2× inf2.24xlarge) | 2× throughput, halves per-user latency at load | 2× instance cost (~$9.96/hr) |
| **Upgrade to inf2.48xlarge** | 2× NeuronCores (24), larger context (32K), higher throughput | ~2× per-instance cost but better per-token efficiency |
| **Increase max_model_len** to 16K | Enables longer prompts/responses at cost of reduced batch capacity | Same instance, may reduce max concurrent |
| **Horizontal autoscaling** (HPA) | Scale replicas based on request queue depth | Pay-per-use, optimal for variable load |

---

## Capacity Planning: 100 Developers

### Developer Token Consumption: Industry Data

Based on industry research and published usage data (sources: [abhs.in cost analysis](https://www.abhs.in/blog/how-much-do-llm-apis-really-cost-5-workloads-2026), [Claude Code cost docs](https://code.claude.com/docs/en/costs.md), [Cursor usage analysis](https://dredyson.com/the-insiders-guide-to-cursors-token-inflation-why-your-usage-shows-10x-reality/)):

| Usage Profile | Input Tokens/Month | Output Tokens/Month | Output Tokens/Working Day | Requests/Day |
|---|---|---|---|---|
| **Light** (occasional prompts) | 100K | 40K | ~1,800 | 30-50 |
| **Moderate** (industry average) | 200K | 80K | ~3,600 | 80-120 |
| **Heavy** (active coding assistant user) | 500K | 200K | ~9,100 | 150-250 |
| **Power user** (continuous agent/automation) | 2M+ | 800K+ | ~36,400+ | 500+ |

> **Industry benchmark**: Code assistant workloads average **200,000 input tokens + 80,000 output tokens per developer per month** for daily use including completions, explanations, and refactors. This translates to ~3,600 output tokens per working day (22 days/month).

> **Enterprise planning guidance** (from Claude Code/Anthropic): For teams of 100-500 users, allocate **15,000-20,000 tokens per minute (TPM) per user** as peak capacity, accounting for the fact that not all users are active simultaneously.

### Concurrency Model for 100 Developers

Not all 100 developers use the LLM simultaneously. Usage follows a bursty pattern:

| Time Period | Active Users (% of 100) | Concurrent Requests | Rationale |
|---|---|---|---|
| **Off-peak** (nights/weekends) | 5-10% | 1-3 | Minimal activity |
| **Normal working hours** | 30-50% | 5-10 | Typical day, staggered usage |
| **Peak hours** (10am-12pm, 2-4pm) | 50-70% | 10-20 | Busy coding periods |
| **Burst** (team standup/sprint start) | 70-90% | 15-30 | Short-lived spikes |

**Key assumption**: At peak, ~15-20% of developers will have an active request in-flight simultaneously (coding requests take 5-30 seconds, but developers spend most time reading/editing code between requests).

### Calculating Required Nodes

#### Approach 1: Average Daily Token Budget

```
100 developers × 3,600 output tokens/working day = 360,000 output tokens/day
360,000 tokens / 8 working hours = 45,000 tokens/hour = 12.5 output tokens/sec

→ 1 inf2.24xlarge (110 tok/s capacity) handles this at ~11% utilization
```

**But average throughput is misleading** — it doesn't account for peak concurrency.

#### Approach 2: Peak Concurrent Load (Recommended)

Target SLA: **TTFT < 1 second, per-user output speed > 12 tokens/sec** (smooth streaming)

From our benchmarks, a single inf2.24xlarge delivers:
- At concurrency 6: ~88 output tok/s aggregate, ~15 tok/s per user, TTFT ~555ms ✅
- At concurrency 8: ~99 output tok/s aggregate, ~12 tok/s per user, TTFT ~553ms ✅
- At concurrency 10: ~113 output tok/s aggregate, ~11 tok/s per user, TTFT ~567ms ⚠️ (borderline)

**Peak scenario**: 100 developers → 15-20 concurrent requests at peak

```
Required capacity at peak: 15-20 concurrent request streams
Per inf2.24xlarge: comfortable at 6-8 concurrent requests (good UX)
Nodes needed: ceil(20 / 7) = 3 inf2.24xlarge nodes (with headroom)
```

#### Approach 3: Enterprise Headroom (Production-Grade)

For production deployments, add 50% headroom for:
- Compilation cache misses (first requests after restart)
- Traffic spikes beyond normal peaks
- Node maintenance/rolling updates (need N+1 capacity)

```
Base: 3 nodes
Headroom (+50%): ceil(3 × 1.5) = 5 inf2.24xlarge nodes
N+1 for maintenance: 5 + 1 = 6 inf2.24xlarge nodes
```

### Node Requirements Summary

| Instance Type | Specs | Nodes for 100 Devs (Good UX) | Nodes (Production w/ Headroom) |
|---|---|---|---|
| **inf2.24xlarge** | 12 NeuronCores, 192 GB HBM, 96 vCPU | **3** | **5-6** |
| **inf2.48xlarge** | 24 NeuronCores, 384 GB HBM, 192 vCPU | **2** | **3** |

### Recommendation for 100 Developers

**Option A (Recommended): 4× inf2.24xlarge with HPA** — 3 baseline + 1 HPA scale-up. Handles 24 concurrent requests with good UX. Best for standard code completion (≤8K context).

**Option B: 3× inf2.48xlarge** — 2 active + 1 standby. Handles 20+ concurrent with 32K context windows. Best for large codebase analysis and RAG with big contexts.

> See [Total Cost of Ownership](#total-cost-of-ownership-tco) for full pricing comparison.

---

## Total Cost of Ownership (TCO)

### Cluster Infrastructure

Every ROSA deployment requires a base set of worker nodes for the OpenShift AI platform (operators, KMM, NFD, Neuron operator), plus the Inferentia inference nodes.

| Component | Instance Type | Count | vCPUs (each) | Total vCPUs | Purpose |
|---|---|---|---|---|---|
| **Platform nodes** | m5.2xlarge | 3 | 8 | 24 | OpenShift AI, operators, monitoring |
| **Inference (Option A)** | inf2.24xlarge | 4 | 96 | 384 | vLLM model serving (100 devs) |
| **Inference (Option B)** | inf2.48xlarge | 3 | 192 | 576 | vLLM model serving (100 devs) |

| Deployment | Total Worker vCPUs | Total Worker Nodes |
|---|---|---|
| **Single inf2.24xlarge** (small team) | 120 (96 + 24) | 4 |
| **Option A**: 4× inf2.24xlarge (100 devs) | 408 (384 + 24) | 7 |
| **Option B**: 3× inf2.48xlarge (100 devs) | 600 (576 + 24) | 6 |

### Cost Components

| # | Cost Component | Billing Model | Notes |
|---|---|---|---|
| 1 | **EC2 Compute** | Per instance-hour | Eligible for EC2 Instance Savings Plans |
| 2 | **ROSA Cluster Fee** | $2,190/year flat per cluster | Fixed regardless of cluster size |
| 3 | **ROSA Worker Node Subscription** | Per 4 vCPU/year | On-demand: $1,500; 1yr: $1,000; 3yr: $667 |
| 4 | **OpenShift AI Subscription** | $0.022 per vCPU/hour | Applies to all worker node vCPUs |

### Pricing Model 1: On-Demand (Hourly)

All EC2 at on-demand rates, ROSA subscriptions at on-demand tier.

**EC2 On-Demand Rates (us-east-2):**

| Instance | On-Demand/hr |
|---|---|
| m5.2xlarge | $0.384 |
| inf2.24xlarge | $6.49 |
| inf2.48xlarge | $12.98 |

#### Single inf2.24xlarge (Small Team, ≤8 devs)

| Cost Component | Calculation | Monthly | Annual |
|---|---|---|---|
| EC2: 1× inf2.24xlarge | $6.49 × 730 hrs | $4,738 | $56,856 |
| EC2: 3× m5.2xlarge | 3 × $0.384 × 730 hrs | $841 | $10,092 |
| ROSA Cluster Fee | $2,190 / 12 | $183 | $2,190 |
| ROSA Subscription (120 vCPU) | 30 units × $1,500 / 12 | $3,750 | $45,000 |
| OpenShift AI (120 vCPU) | 120 × $0.022 × 730 hrs | $1,927 | $23,126 |
| **Total** | | **$11,439/mo** | **$137,264/yr** |

#### Option A: 4× inf2.24xlarge (100 Developers)

| Cost Component | Calculation | Monthly | Annual |
|---|---|---|---|
| EC2: 4× inf2.24xlarge | 4 × $6.49 × 730 hrs | $18,951 | $227,414 |
| EC2: 3× m5.2xlarge | 3 × $0.384 × 730 hrs | $841 | $10,092 |
| ROSA Cluster Fee | $2,190 / 12 | $183 | $2,190 |
| ROSA Subscription (408 vCPU) | 102 units × $1,500 / 12 | $12,750 | $153,000 |
| OpenShift AI (408 vCPU) | 408 × $0.022 × 730 hrs | $6,553 | $78,630 |
| **Total** | | **$39,278/mo** | **$471,326/yr** |
| **Per developer** | | **$393/mo** | **$4,713/yr** |

#### Option B: 3× inf2.48xlarge (100 Developers)

| Cost Component | Calculation | Monthly | Annual |
|---|---|---|---|
| EC2: 3× inf2.48xlarge | 3 × $12.98 × 730 hrs | $28,426 | $341,118 |
| EC2: 3× m5.2xlarge | 3 × $0.384 × 730 hrs | $841 | $10,092 |
| ROSA Cluster Fee | $2,190 / 12 | $183 | $2,190 |
| ROSA Subscription (600 vCPU) | 150 units × $1,500 / 12 | $18,750 | $225,000 |
| OpenShift AI (600 vCPU) | 600 × $0.022 × 730 hrs | $9,636 | $115,632 |
| **Total** | | **$57,836/mo** | **$694,032/yr** |
| **Per developer** | | **$578/mo** | **$6,940/yr** |

### Pricing Model 2: 3-Year Reserved (Optimized)

EC2 with **3-Year EC2 Instance Savings Plan (No Upfront)**, ROSA subscriptions at **3-year** tier.

**EC2 3-Year Instance Savings Plan Rates (No Upfront, us-east-2):**

| Instance | 3yr SP/hr | Savings vs On-Demand |
|---|---|---|
| m5.2xlarge | $0.166 | 57% |
| inf2.24xlarge | $2.80 | 57% |
| inf2.48xlarge | $5.61 | 57% |

#### Single inf2.24xlarge (Small Team, ≤8 devs)

| Cost Component | Calculation | Monthly | Annual |
|---|---|---|---|
| EC2: 1× inf2.24xlarge | $2.80 × 730 hrs | $2,044 | $24,528 |
| EC2: 3× m5.2xlarge | 3 × $0.166 × 730 hrs | $364 | $4,364 |
| ROSA Cluster Fee | $2,190 / 12 | $183 | $2,190 |
| ROSA Subscription (120 vCPU) | 30 units × $667 / 12 | $1,668 | $20,010 |
| OpenShift AI (120 vCPU) | 120 × $0.022 × 730 hrs | $1,927 | $23,126 |
| **Total** | | **$6,186/mo** | **$74,218/yr** |

#### Option A: 4× inf2.24xlarge (100 Developers)

| Cost Component | Calculation | Monthly | Annual |
|---|---|---|---|
| EC2: 4× inf2.24xlarge | 4 × $2.80 × 730 hrs | $8,176 | $98,112 |
| EC2: 3× m5.2xlarge | 3 × $0.166 × 730 hrs | $364 | $4,364 |
| ROSA Cluster Fee | $2,190 / 12 | $183 | $2,190 |
| ROSA Subscription (408 vCPU) | 102 units × $667 / 12 | $5,669 | $68,034 |
| OpenShift AI (408 vCPU) | 408 × $0.022 × 730 hrs | $6,553 | $78,630 |
| **Total** | | **$20,945/mo** | **$251,330/yr** |
| **Per developer** | | **$209/mo** | **$2,513/yr** |

#### Option B: 3× inf2.48xlarge (100 Developers)

| Cost Component | Calculation | Monthly | Annual |
|---|---|---|---|
| EC2: 3× inf2.48xlarge | 3 × $5.61 × 730 hrs | $12,286 | $147,434 |
| EC2: 3× m5.2xlarge | 3 × $0.166 × 730 hrs | $364 | $4,364 |
| ROSA Cluster Fee | $2,190 / 12 | $183 | $2,190 |
| ROSA Subscription (600 vCPU) | 150 units × $667 / 12 | $8,338 | $100,050 |
| OpenShift AI (600 vCPU) | 600 × $0.022 × 730 hrs | $9,636 | $115,632 |
| **Total** | | **$30,807/mo** | **$369,670/yr** |
| **Per developer** | | **$308/mo** | **$3,697/yr** |

### 3-Year TCO Comparison

| Deployment | On-Demand (3yr) | 3yr Reserved (3yr) | Savings | Per Dev/mo (Reserved) |
|---|---|---|---|---|
| **Single inf2.24xlarge** | $411,792 | $222,654 | **46%** | N/A (small team) |
| **Option A**: 4× inf2.24xlarge | $1,413,978 | $753,990 | **47%** | **$209/mo** |
| **Option B**: 3× inf2.48xlarge | $2,082,096 | $1,109,010 | **47%** | **$308/mo** |

### Cost Breakdown Visualization (Option A, 3-Year Reserved)

```
EC2 Compute (inf2 + m5)     ███████████████████         41%  ($102,476/yr)
ROSA Subscription            █████████████               27%  ($68,034/yr)
OpenShift AI Subscription    ████████████                31%  ($78,630/yr)
ROSA Cluster Fee             ▏                            1%  ($2,190/yr)
                             ─────────────────────────────────
                             Total: $251,330/yr
```

### Key Pricing Insights

1. **3-year commitment cuts total cost by ~47%** — EC2 savings of 57% dominate, partially offset by the non-discountable OpenShift AI subscription ($0.022/vCPU/hr).

2. **OpenShift AI subscription is the largest non-EC2 cost** — at 31% of total (3yr reserved), it exceeds the ROSA subscription. This is driven by high vCPU counts on Inferentia nodes (96 vCPU per inf2.24xlarge).

3. **Option A (4× inf2.24xlarge) is 32% cheaper than Option B** (3× inf2.48xlarge) at $209/dev/mo vs $308/dev/mo, primarily because fewer total vCPUs (408 vs 600) means lower ROSA and OpenShift AI subscription costs.

4. **ROSA cluster fee is negligible** at $2,190/year (<1% of total cost), making the managed Kubernetes overhead minimal.

---

## Conclusions & Recommendations

### Summary

- **Qwen3-Coder-30B-A3B on Inferentia2** achieves **~24 output tokens/sec** single-user with a **523ms TTFT** and **41ms inter-token latency** on an inf2.24xlarge instance.
- At realistic concurrency (6-10 users), aggregate output throughput reaches **~88-154 tokens/sec** while maintaining acceptable per-user latency.
- The MoE architecture (only 3.3B active params per token out of 30.5B total) is efficient for inference, but the full parameter footprint requires significant HBM for weight storage.
- With `tp_degree=8` and `max_model_len=8192`, the deployment uses 8 of 12 available NeuronCores due to the hidden_size (2048) divisibility constraint.

### Key Findings

1. **TTFT is remarkably stable** across concurrency levels for prompts ≤1024 tokens — staying at ~495-570ms from 1 to 10+ concurrent users. For 2048-token prompts, TTFT increases to ~865-946ms. Only at extreme throughput mode (512 concurrency) does TTFT degrade severely to 7-36 seconds.

2. **ITL (Inter-Token Latency) degrades linearly** with concurrency — from 41ms (1 user) to ~56-92ms (10+ users). Large prompts (2048 tokens) show slightly higher baseline ITL (~47ms) due to KV cache pressure.

3. **Aggregate output throughput scales sub-linearly** — 1 user: 24 tok/s → 6 users: ~77-88 tok/s → 10 users: ~103-154 tok/s. Approximately 4.7× improvement at 10× the users.

4. **Token size has minimal impact on per-token speed** — ITL stays at ~41ms across 128-1024 output tokens at synchronous mode. Larger token configs achieve higher aggregate throughput by amortizing overhead.

5. **Maximum daily capacity**: ~9.5M-13.3M output tokens/day at sustained load, or ~4.8-6.7M tokens/day at 50% utilization.

6. **Cost efficiency (3yr reserved)**: At ~110-154 output tokens/sec sustained, the all-in cost is approximately **$209/developer/month** for 100 developers including all Red Hat subscriptions, or **$6,186/month** for a small team deployment.

### Recommendations

- **Small team (≤8 devs)**: Single inf2.24xlarge + 3× m5.2xlarge. $6,186/mo (3yr reserved). 24 tok/s single-user with fluid streaming.

- **100 developers (Option A)**: 4× inf2.24xlarge + 3× m5.2xlarge with HPA. **$20,945/mo ($209/dev, 3yr reserved)**. Handles 24 concurrent requests with good UX, scales to 32 at peak. Best for standard code completion (≤8K context).

- **100 developers (Option B)**: 3× inf2.48xlarge + 3× m5.2xlarge. **$30,807/mo ($308/dev, 3yr reserved)**. 32K context windows for large codebase analysis and RAG. Higher cost driven by more vCPUs and proportionally higher ROSA/OpenShift AI subscriptions.

---

*Generated on: March 27, 2026*
*Benchmarking tool: GuideLLM v0.5.4 (Red Hat / Neural Magic)*
*Platform: ROSA HCP 4.21.6 on AWS us-east-2*
*Benchmarks executed from: in-cluster pod (Python 3.12, pod-to-service networking)*

---

## Appendix: Raw GuideLLM Test Results

The complete raw output from each GuideLLM sweep benchmark is reproduced below for reference and reproducibility.

### Raw Test 1: 128 prompt / 128 output tokens

**Request Latency Statistics (Completed Requests)**
```
| Strategy    | Req Latency Sec | TTFT ms         | ITL ms     | TPOT ms       |
|             | Mdn     | p95    | Mdn     | p95     | Mdn  | p95  | Mdn   | p95   |
|-------------|---------|--------|---------|---------|------|------|-------|-------|
| synchronous | 5.7     | 5.8    | 523.4   | 523.6   | 40.9 | 41.4 | 44.6  | 45.2  |
| throughput  | 26.0    | 39.0   | 17400.2 | 32830.6 | 71.5 | 98.3 | 203.1 | 304.7 |
| constant    | 6.3     | 6.4    | 546.1   | 568.1   | 45.4 | 46.1 | 49.3  | 50.0  |
| constant    | 6.9     | 7.1    | 555.2   | 574.0   | 49.9 | 51.3 | 54.0  | 55.2  |
| constant    | 7.5     | 7.5    | 555.2   | 573.9   | 54.4 | 54.9 | 58.2  | 58.9  |
| constant    | 8.0     | 8.1    | 554.8   | 570.9   | 58.8 | 59.2 | 62.5  | 63.2  |
| constant    | 9.2     | 9.2    | 549.5   | 566.2   | 67.8 | 67.9 | 71.5  | 71.8  |
| constant    | 10.1    | 10.3   | 552.3   | 574.7   | 75.3 | 76.9 | 79.1  | 80.6  |
| constant    | 11.4    | 11.5   | 548.2   | 568.3   | 85.2 | 85.9 | 88.8  | 89.6  |
| constant    | 12.2    | 12.2   | 567.3   | 574.8   | 91.5 | 91.6 | 95.2  | 95.3  |
```

**Server Throughput Statistics (All Requests)**
```
| Strategy    | Req/s       | Concurrency    | Input tok/s     | Output tok/s    | Total tok/s     |
|             | Mdn | Mean  | Mdn   | Mean   | Mdn   | Mean   | Mdn    | Mean   | Mdn   | Mean   |
|-------------|-----|-------|-------|--------|-------|--------|--------|--------|-------|--------|
| synchronous | 0.2 | 0.2   | 1.0   | 1.0    | 23.8  | 28.5   | 24.5   | 22.7   | 24.5  | 46.8   |
| throughput  | 0.5 | 1.1   | 512.0 | 508.2  | 279.5 | 1816.5 | 119.6  | 159.4  | 127.3 | 1975.9 |
| constant    | 0.3 | 0.2   | 2.0   | 1.7    | 37.9  | 42.6   | 43.4   | 34.9   | 43.4  | 74.5   |
| constant    | 0.4 | 0.3   | 3.0   | 2.5    | 53.3  | 58.0   | 41.0   | 47.3   | 41.0  | 101.5  |
| constant    | 0.5 | 0.4   | 4.0   | 3.4    | 68.7  | 73.0   | 45.9   | 59.7   | 45.9  | 130.3  |
| constant    | 0.6 | 0.5   | 5.0   | 4.4    | 83.4  | 88.3   | 61.6   | 71.9   | 61.9  | 157.4  |
| constant    | 0.7 | 0.5   | 6.0   | 5.8    | 99.5  | 103.7  | 68.9   | 83.0   | 69.5  | 183.8  |
| constant    | 0.8 | 0.6   | 8.0   | 7.2    | 114.8 | 118.8  | 79.0   | 92.7   | 79.8  | 210.5  |
| constant    | 0.9 | 0.6   | 10.0  | 8.9    | 130.6 | 134.1  | 80.3   | 102.9  | 81.6  | 235.3  |
| constant    | 1.0 | 0.7   | 13.0  | 10.5   | 145.1 | 151.8  | 94.7   | 112.9  | 95.1  | 264.7  |
```

### Raw Test 2: 128 prompt / 256 output tokens

**Request Latency Statistics (Completed Requests)**
```
| Strategy    | Req Latency Sec | TTFT ms         | ITL ms     | TPOT ms       |
|             | Mdn     | p95    | Mdn    | p95     | Mdn  | p95  | Mdn  | p95   |
|-------------|---------|--------|--------|---------|------|------|------|-------|
| synchronous | 10.9    | 11.0   | 523.5  | 523.6   | 40.9 | 40.9 | 42.7 | 42.8  |
| throughput  | 18.2    | 36.6   | 7791.9 | 25529.9 | 54.6 | 69.5 | 71.2 | 142.8 |
| constant    | 11.5    | 11.5   | 542.3  | 550.2   | 43.0 | 43.1 | 44.9 | 45.1  |
| constant    | 12.1    | 12.1   | 553.1  | 578.5   | 45.3 | 45.5 | 47.3 | 47.4  |
| constant    | 12.1    | 12.1   | 550.1  | 571.2   | 45.3 | 45.3 | 47.3 | 47.4  |
| constant    | 12.8    | 12.9   | 550.8  | 568.5   | 48.0 | 48.3 | 50.0 | 50.3  |
| constant    | 13.3    | 13.4   | 558.0  | 577.6   | 49.9 | 50.2 | 51.8 | 52.2  |
| constant    | 13.7    | 13.9   | 547.5  | 567.7   | 51.7 | 52.4 | 53.6 | 54.4  |
| constant    | 14.3    | 14.4   | 554.6  | 571.2   | 53.9 | 54.4 | 55.9 | 56.4  |
| constant    | 14.9    | 15.0   | 539.6  | 577.5   | 56.2 | 56.5 | 58.2 | 58.5  |
```

**Server Throughput Statistics (All Requests)**
```
| Strategy    | Req/s       | Concurrency    | Input tok/s    | Output tok/s    | Total tok/s     |
|             | Mdn | Mean  | Mdn   | Mean   | Mdn  | Mean   | Mdn    | Mean   | Mdn   | Mean   |
|-------------|-----|-------|-------|--------|------|--------|--------|--------|-------|--------|
| synchronous | 0.1 | 0.1   | 1.0   | 1.0    | 24.8 | 18.6   | 24.5   | 23.8   | 24.5  | 36.4   |
| throughput  | 0.2 | 0.5   | 512.0 | 508.2  | 24.7 | 1879.1 | 174.9  | 226.9  | 180.6 | 2106.1 |
| constant    | 0.1 | 0.1   | 1.0   | 1.4    | 17.0 | 22.6   | 23.3   | 30.2   | 23.3  | 47.4   |
| constant    | 0.1 | 0.1   | 2.0   | 2.0    | 24.9 | 29.8   | 44.1   | 42.9   | 44.1  | 68.2   |
| constant    | 0.2 | 0.2   | 3.0   | 2.5    | 32.8 | 37.5   | 50.1   | 55.3   | 50.2  | 88.9   |
| constant    | 0.3 | 0.2   | 4.0   | 3.2    | 40.7 | 45.8   | 55.6   | 65.8   | 55.8  | 107.2  |
| constant    | 0.1 | 0.2   | 4.0   | 3.9    | 48.7 | 53.5   | 61.1   | 76.9   | 61.2  | 127.5  |
| constant    | 0.1 | 0.2   | 5.0   | 4.6    | 56.5 | 61.3   | 72.4   | 88.1   | 72.9  | 146.5  |
| constant    | 0.1 | 0.3   | 6.0   | 5.4    | 64.7 | 69.1   | 78.6   | 99.3   | 79.2  | 165.5  |
| constant    | 0.1 | 0.3   | 8.0   | 6.2    | 72.4 | 78.1   | 84.8   | 108.8  | 85.4  | 186.9  |
```

### Raw Test 3: 256 prompt / 256 output tokens

**Request Latency Statistics (Completed Requests)**
```
| Strategy    | Req Latency Sec | TTFT ms         | ITL ms     | TPOT ms       |
|             | Mdn     | p95    | Mdn    | p95     | Mdn  | p95  | Mdn  | p95   |
|-------------|---------|--------|--------|---------|------|------|------|-------|
| synchronous | 10.9    | 11.0   | 522.7  | 523.8   | 40.9 | 41.2 | 42.7 | 43.0  |
| throughput  | 18.2    | 36.4   | 7782.4 | 25526.2 | 54.2 | 69.4 | 71.1 | 142.3 |
| constant    | 11.6    | 11.6   | 570.3  | 574.9   | 42.9 | 43.1 | 45.0 | 45.2  |
| constant    | 12.1    | 12.2   | 540.4  | 563.5   | 45.5 | 45.8 | 47.4 | 47.8  |
| constant    | 12.1    | 12.2   | 559.2  | 578.2   | 45.3 | 45.7 | 47.3 | 47.7  |
| constant    | 12.7    | 12.8   | 548.8  | 572.0   | 47.4 | 47.8 | 49.4 | 49.8  |
| constant    | 13.3    | 13.3   | 555.8  | 565.2   | 49.8 | 50.1 | 51.8 | 52.0  |
| constant    | 13.7    | 13.9   | 544.8  | 557.8   | 51.7 | 52.3 | 53.7 | 54.3  |
| constant    | 14.3    | 14.4   | 552.4  | 565.0   | 53.9 | 54.3 | 55.9 | 56.3  |
| constant    | 14.9    | 14.9   | 537.8  | 567.0   | 56.2 | 56.4 | 58.1 | 58.4  |
```

**Server Throughput Statistics (All Requests)**
```
| Strategy    | Req/s       | Concurrency    | Input tok/s     | Output tok/s    | Total tok/s     |
|             | Mdn | Mean  | Mdn   | Mean   | Mdn   | Mean   | Mdn    | Mean   | Mdn   | Mean   |
|-------------|-----|-------|-------|--------|-------|--------|--------|--------|-------|--------|
| synchronous | 0.1 | 0.1   | 1.0   | 1.0    | 47.9  | 36.0   | 24.5   | 23.7   | 24.5  | 48.2   |
| throughput  | 0.2 | 0.5   | 512.0 | 507.3  | 49.1  | 3763.0 | 175.5  | 227.6  | 180.9 | 3990.7 |
| constant    | 0.1 | 0.1   | 1.0   | 1.4    | 33.1  | 43.9   | 23.3   | 30.2   | 23.3  | 63.7   |
| constant    | 0.1 | 0.1   | 2.0   | 2.0    | 48.3  | 57.9   | 44.1   | 42.8   | 44.1  | 91.9   |
| constant    | 0.2 | 0.2   | 3.0   | 2.5    | 63.7  | 72.8   | 48.0   | 55.1   | 48.1  | 120.2  |
| constant    | 0.3 | 0.2   | 4.0   | 3.2    | 79.4  | 89.2   | 56.9   | 65.8   | 57.1  | 155.0  |
| constant    | 0.1 | 0.2   | 4.0   | 3.9    | 94.5  | 103.7  | 63.8   | 77.0   | 64.0  | 175.4  |
| constant    | 0.1 | 0.2   | 5.0   | 4.6    | 109.8 | 118.8  | 70.4   | 88.0   | 70.8  | 201.7  |
| constant    | 0.1 | 0.3   | 6.0   | 5.4    | 125.6 | 134.1  | 79.4   | 99.3   | 80.0  | 228.0  |
| constant    | 0.1 | 0.3   | 8.0   | 6.2    | 140.6 | 149.8  | 87.9   | 108.6  | 88.2  | 251.8  |
```

### Raw Test 4: 512 prompt / 512 output tokens

**Request Latency Statistics (Completed Requests)**
```
| Strategy    | Req Latency Sec | TTFT ms         | ITL ms     | TPOT ms       |
|             | Mdn     | p95    | Mdn    | p95     | Mdn  | p95  | Mdn  | p95   |
|-------------|---------|--------|--------|---------|------|------|------|-------|
| synchronous | 21.5    | 21.6   | 494.6  | 522.5   | 41.0 | 41.3 | 41.9 | 42.1  |
| throughput  | 28.9    | 57.7   | 7777.8 | 36225.6 | 48.0 | 55.2 | 56.5 | 112.6 |
| constant    | 22.4    | 22.4   | 501.1  | 501.1   | 42.9 | 42.9 | 43.8 | 43.8  |
| constant    | 23.0    | 23.0   | 498.5  | 543.2   | 43.9 | 44.0 | 44.8 | 45.0  |
| constant    | 24.0    | 24.2   | 499.8  | 538.4   | 46.0 | 46.2 | 46.9 | 47.2  |
| constant    | 24.6    | 25.4   | 495.8  | 558.6   | 47.3 | 48.5 | 48.1 | 49.5  |
| constant    | 25.7    | 25.7   | 541.7  | 543.6   | 49.2 | 49.2 | 50.2 | 50.2  |
| constant    | 26.7    | 26.9   | 536.0  | 572.5   | 51.3 | 51.6 | 52.2 | 52.6  |
| constant    | 28.4    | 28.5   | 495.0  | 576.4   | 54.6 | 54.7 | 55.5 | 55.7  |
| constant    | 29.3    | 29.4   | 495.9  | 534.5   | 56.3 | 56.4 | 57.2 | 57.4  |
```

**Server Throughput Statistics (All Requests)**
```
| Strategy    | Req/s       | Concurrency    | Input tok/s     | Output tok/s    | Total tok/s     |
|             | Mdn | Mean  | Mdn   | Mean   | Mdn   | Mean   | Mdn    | Mean   | Mdn   | Mean   |
|-------------|-----|-------|-------|--------|-------|--------|--------|--------|-------|--------|
| synchronous | 0.0 | 0.0   | 1.0   | 1.0    | 48.1  | 48.1   | 24.2   | 24.1   | 24.2  | 48.5   |
| throughput  | 0.2 | 0.5   | 512.0 | 505.5  | 48.5  | 4728.9 | 220.7  | 286.3  | 224.1 | 5015.3 |
| constant    | 0.0 | 0.0   | 2.0   | 1.7    | 49.7  | 74.5   | 46.6   | 40.2   | 46.6  | 90.8   |
| constant    | 0.1 | 0.1   | 3.0   | 2.6    | 82.2  | 102.6  | 50.4   | 60.1   | 50.5  | 143.7  |
| constant    | 0.1 | 0.1   | 4.0   | 3.6    | 114.8 | 133.6  | 60.4   | 79.1   | 60.5  | 195.8  |
| constant    | 0.1 | 0.1   | 5.0   | 4.5    | 147.3 | 165.3  | 75.8   | 97.7   | 76.8  | 247.2  |
| constant    | 0.1 | 0.1   | 6.0   | 5.5    | 179.5 | 197.5  | 81.6   | 114.4  | 81.9  | 298.8  |
| constant    | 0.1 | 0.1   | 7.0   | 6.5    | 212.4 | 229.5  | 96.0   | 130.0  | 97.1  | 345.8  |
| constant    | 0.0 | 0.0   | 8.0   | 7.5    | 245.2 | 261.9  | 98.8   | 138.2  | 99.6  | 396.9  |
| constant    | 0.0 | 0.0   | 8.0   | 8.5    | 277.2 | 294.1  | 95.1   | 154.2  | 95.5  | 441.6  |
```

### Raw Test 5: 1024 prompt / 512 output tokens

**Request Latency Statistics (Completed Requests)**
```
| Strategy    | Req Latency Sec | TTFT ms         | ITL ms     | TPOT ms       |
|             | Mdn     | p95    | Mdn    | p95     | Mdn  | p95  | Mdn  | p95   |
|-------------|---------|--------|--------|---------|------|------|------|-------|
| synchronous | 21.4    | 21.5   | 496.8  | 522.6   | 40.9 | 41.0 | 41.7 | 42.0  |
| throughput  | 28.7    | 57.3   | 7775.4 | 35959.5 | 47.5 | 55.1 | 56.0 | 112.0 |
| constant    | 22.6    | 22.6   | 505.2  | 505.2   | 43.2 | 43.2 | 44.1 | 44.1  |
| constant    | 23.0    | 23.1   | 501.3  | 549.1   | 43.9 | 44.0 | 44.8 | 45.0  |
| constant    | 24.1    | 24.1   | 498.6  | 540.0   | 46.1 | 46.2 | 47.0 | 47.2  |
| constant    | 24.7    | 24.7   | 553.9  | 568.2   | 47.3 | 47.3 | 48.3 | 48.3  |
| constant    | 25.7    | 25.8   | 541.1  | 543.1   | 49.3 | 49.3 | 50.2 | 50.3  |
| constant    | 26.8    | 26.9   | 495.3  | 573.8   | 51.4 | 51.6 | 52.3 | 52.6  |
| constant    | 28.4    | 28.6   | 496.3  | 537.2   | 54.7 | 54.9 | 55.5 | 55.9  |
| constant    | 29.4    | 29.5   | 498.2  | 536.0   | 56.5 | 56.7 | 57.3 | 57.7  |
```

**Server Throughput Statistics (All Requests)**
```
| Strategy    | Req/s       | Concurrency    | Input tok/s     | Output tok/s    | Total tok/s     |
|             | Mdn | Mean  | Mdn   | Mean   | Mdn   | Mean   | Mdn    | Mean   | Mdn   | Mean   |
|-------------|-----|-------|-------|--------|-------|--------|--------|--------|-------|--------|
| synchronous | 0.0 | 0.0   | 1.0   | 1.0    | 96.5  | 96.5   | 24.4   | 24.2   | 24.4  | 72.9   |
| throughput  | 0.5 | 0.5   | 512.0 | 494.0  | 96.6  | 9508.3 | 223.3  | 288.0  | 227.0 | 9796.3 |
| constant    | 0.0 | 0.0   | 2.0   | 1.7    | 98.6  | 147.9  | 46.3   | 40.2   | 46.3  | 140.6  |
| constant    | 0.1 | 0.1   | 3.0   | 2.6    | 163.1 | 203.5  | 50.7   | 60.1   | 50.8  | 226.2  |
| constant    | 0.1 | 0.1   | 4.0   | 3.6    | 227.8 | 265.2  | 63.0   | 79.6   | 63.3  | 311.1  |
| constant    | 0.1 | 0.1   | 5.0   | 4.5    | 292.5 | 328.1  | 73.8   | 98.1   | 74.2  | 395.0  |
| constant    | 0.1 | 0.1   | 6.0   | 5.5    | 356.4 | 392.0  | 89.9   | 114.5  | 90.4  | 480.1  |
| constant    | 0.1 | 0.1   | 7.0   | 6.5    | 421.6 | 455.3  | 94.0   | 129.6  | 94.4  | 558.8  |
| constant    | 0.0 | 0.0   | 8.0   | 7.5    | 486.8 | 519.8  | 101.5  | 137.5  | 102.1 | 649.5  |
| constant    | 0.0 | 0.0   | 8.0   | 8.5    | 550.3 | 584.1  | 92.6   | 154.1  | 93.4  | 721.8  |
```

### Raw Test 6: 2048 prompt / 1024 output tokens

**Request Latency Statistics (Completed Requests)**
```
| Strategy    | Req Latency Sec | TTFT ms         | ITL ms     | TPOT ms      |
|             | Mdn     | p95    | Mdn    | p95     | Mdn  | p95  | Mdn  | p95  |
|-------------|---------|--------|--------|---------|------|------|------|------|
| synchronous | 48.8    | 49.0   | 865.1  | 891.1   | 46.8 | 47.0 | 47.6 | 47.9 |
| throughput  | 61.6    | 61.6   | 6814.8 | 13597.7 | 52.7 | 59.4 | 60.2 | 60.2 |
| constant    | 49.7    | 49.9   | 871.0  | 945.2   | 47.7 | 47.8 | 48.5 | 48.7 |
| constant    | 50.9    | 51.0   | 910.7  | 948.0   | 48.9 | 49.0 | 49.7 | 49.8 |
| constant    | 51.8    | 51.9   | 912.8  | 955.2   | 49.7 | 49.8 | 50.5 | 50.7 |
| constant    | 52.6    | 52.7   | 927.6  | 938.4   | 50.5 | 50.6 | 51.4 | 51.4 |
| constant    | 54.3    | 54.6   | 933.2  | 945.3   | 52.2 | 52.5 | 53.1 | 53.4 |
| constant    | 55.2    | 55.2   | 934.9  | 946.1   | 53.0 | 53.1 | 53.9 | 53.9 |
| constant    | 56.2    | 56.3   | 921.3  | 938.8   | 54.1 | 54.1 | 54.9 | 55.0 |
| constant    | 58.0    | 58.2   | 921.9  | 946.2   | 55.8 | 55.9 | 56.6 | 56.8 |
```

**Server Throughput Statistics (All Requests)**
```
| Strategy    | Req/s       | Concurrency    | Input tok/s     | Output tok/s    | Total tok/s     |
|             | Mdn | Mean  | Mdn   | Mean   | Mdn   | Mean   | Mdn    | Mean   | Mdn   | Mean   |
|-------------|-----|-------|-------|--------|-------|--------|--------|--------|-------|--------|
| synchronous | 0.0 | 0.0   | 1.0   | 1.0    | 84.3  | 84.3   | 21.3   | 21.1   | 21.3  | 63.6   |
| throughput  | 0.1 | 0.2   | 512.0 | 497.1  | 89.9  | 9065.4 | 207.2  | 266.3  | 209.5 | 9331.7 |
| constant    | 0.0 | 0.0   | 1.0   | 1.4    | 65.5  | 98.3   | 21.4   | 29.0   | 21.4  | 95.2   |
| constant    | 0.0 | 0.0   | 2.0   | 2.2    | 108.4 | 135.4  | 41.1   | 44.9   | 41.1  | 154.4  |
| constant    | 0.0 | 0.0   | 3.0   | 3.0    | 151.0 | 176.2  | 50.4   | 60.5   | 50.5  | 217.5  |
| constant    | 0.0 | 0.0   | 5.0   | 3.8    | 193.9 | 218.0  | 61.8   | 76.0   | 61.8  | 272.5  |
| constant    | 0.0 | 0.1   | 6.0   | 4.7    | 237.0 | 260.5  | 69.6   | 90.5   | 69.9  | 329.7  |
| constant    | 0.0 | 0.1   | 7.0   | 5.5    | 279.8 | 302.9  | 78.7   | 103.8  | 78.8  | 397.1  |
| constant    | 0.0 | 0.1   | 8.0   | 6.4    | 322.7 | 345.5  | 95.9   | 119.3  | 96.0  | 448.8  |
| constant    | 0.0 | 0.1   | 8.0   | 7.3    | 365.5 | 388.2  | 102.1  | 130.5  | 102.2 | 514.3  |
```
