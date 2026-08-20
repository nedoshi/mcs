# Failover Runbook — ARO ↔ ROSA HCP Cross-Cloud DR

Execute when primary cloud/region is declared unavailable. Adapt steps for your primary direction (ARO→ROSA or ROSA→ARO).

**Related:** [Failback Runbook](./failback-runbook-aro-rosa.md) · [Cross-Cloud DR Guide](../../docs/guide/cross-cloud-dr-aro-rosa/README.md)

---

## Disaster Declaration

| Condition | Threshold | Authority |
|-----------|-----------|-----------|
| Primary cluster API unreachable | > ___ minutes | _____________ |
| Primary cloud regional outage | Confirmed by cloud provider | _____________ |
| Data corruption / ransomware | Security incident commander | _____________ |

**Do not failover** for single-pod failures — use standard incident response.

Record: **Incident ID** ______ | **Declared by** ______ | **Time (UTC)** ______

---

## Recovery Sequence

```
1. Declare disaster
2. Data layer (promote replica / restore OADP)
3. Platform (scale DR cluster if Pilot Light)
4. GitOps verification
5. Traffic cutover (DNS / global LB)
6. Smoke tests
7. Stakeholder communication
```

---

## Cold Tier (Backup & Restore)

Use when DR cluster was **not** pre-provisioned.

### Step 1: Provision DR Cluster

```bash
# Scenario A: ROSA DR
cd cluster-creation-cloud/aws/tf-rosa
make apply TFVARS=../../cross-cloud-dr/environments/rosa-dr.tfvars.example

# Scenario B: ARO DR
cd cluster-creation-cloud/azure/terraform-aro
make create  # or make create-private
```

**Start timer** — RTO measurement begins.

### Step 2: Bootstrap Platform

- Import cluster to ACM — [ACM GitOps Setup](./acm-gitops-setup.md)
- Verify Argo CD syncs baseline + overlay charts
- Confirm Entra ID login works

### Step 3: Restore Data

```bash
# OADP restore (see oadp_cross_cloud_s3_guide.md)
velero restore create failover-restore-$(date +%Y%m%d) \
  --from-backup <latest-backup> \
  --storage-class-mappings managed-csi=gp3-csi-kms \
  --include-namespaces production

# DB: promote replica or restore from native backup
```

### Step 4: Traffic Cutover

See [Traffic Steering Guide](./traffic-steering-guide.md).

### Step 5: Smoke Tests

- [ ] Application health endpoint returns 200
- [ ] User login via Entra ID succeeds
- [ ] Critical transaction path tested (read + write)
- [ ] Monitoring/alerts firing on DR cluster

---

## Pilot Light Tier

DR cluster exists with minimal workers; apps scaled to zero or reduced.

### Step 1: Scale DR Cluster

```bash
# ROSA: scale machine pool
rosa edit machinepool <pool-id> --replicas=<production-count>

# ARO: patch MachineSet or enable cluster autoscaler
oc scale deployment/<app> --replicas=<prod-count> -n production
```

### Step 2: Promote / Sync Data

- Final async replication sync or last OADP backup restore
- Promote DB replica — [Data Replication Guide](./data-replication-guide.md)

### Step 3–5: Same as Cold (GitOps verify, traffic, smoke tests)

---

## Active/Passive Tier

DR cluster full-size; workloads deployed but idle.

### Step 1: Stop Primary Writes

Enable maintenance mode on primary app (if primary partially reachable).

### Step 2: Promote Data

```sql
-- PostgreSQL example
ALTER SUBSCRIPTION dr_sub DISABLE;
-- Verify lag = 0 before cutover
```

### Step 3: Traffic Cutover

Repoint global DNS / LB to DR ingress — no cluster scale-up needed.

### Step 4: Smoke Tests

Same checklist as Cold tier.

---

## Active/Active Tier

Regional loss reduces capacity; global LB should auto-route away from failed region.

1. Confirm health probes removed failed region from rotation
2. Scale remaining region if needed for full capacity
3. Investigate data consistency for multi-write apps
4. Communicate degraded capacity if applicable

---

## Communication Template

```
Subject: [SEV-1] Cross-Cloud Failover — Production on <DR Cloud>

We have declared a disaster affecting our primary <Azure/AWS> region.
Production traffic is being redirected to <DR cloud>.
Estimated impact: <duration>.
Next update: <time UTC>.
```

---

## Post-Failover

- [ ] Record actual RTO (declare → smoke test pass)
- [ ] Record actual RPO (data loss window)
- [ ] Open provider support cases (Azure + Red Hat OCM)
- [ ] Schedule failback planning — [Failback Runbook](./failback-runbook-aro-rosa.md)
- [ ] Update [DR Test Results](./dr-test-results-template.md)

---

## Rollback (Failover Aborted)

If primary recovers during failover **before** traffic cutover:

1. Stop DR restore/promotion
2. Re-enable primary replication direction
3. Do **not** cut DNS
4. Document false alarm; review declaration threshold
