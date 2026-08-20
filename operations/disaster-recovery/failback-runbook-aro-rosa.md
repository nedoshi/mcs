# Failback Runbook — DR Cloud → Primary Cloud

Execute after primary cloud/region is restored and validated. **Failback is the most commonly skipped DR step** — rehearse annually.

**Related:** [Failover Runbook](./failover-runbook-aro-rosa.md) · [Cross-Cloud DR Guide](../../docs/guide/cross-cloud-dr-aro-rosa/README.md)

---

## Prerequisites

- [ ] Primary cloud region confirmed healthy by cloud provider
- [ ] Primary cluster reprovisioned or recovered (IaC apply if destroyed)
- [ ] Primary cluster passes health checks (`oc get co`, `oc get nodes`)
- [ ] Stakeholders notified of planned failback window
- [ ] Maintenance window scheduled (expect brief read-only period)

---

## Failback Sequence

```
1. Enable read-only / maintenance on DR (stop new writes)
2. Final sync: DR → Primary (DB reverse replication or OADP backup from DR)
3. Verify data parity on primary
4. GitOps sync to primary cluster
5. Traffic cutover to primary
6. Re-establish primary → DR replication
7. DR cluster returns to standby mode
8. Smoke tests on primary
```

---

## Step 1: Quiesce DR

```bash
# Scale apps to 0 or enable maintenance mode
oc scale deployment --all --replicas=0 -n production
# Or ingress maintenance page
```

Record **failback start time** (UTC): ____________

---

## Step 2: Sync Data to Primary

### Database (reverse logical replication)

1. Create publication on DR RDS
2. Create subscription on primary Azure PostgreSQL pointing to DR
3. Wait for lag = 0

### OADP (if file-level sync needed)

```bash
# Backup from DR cluster
velero backup create failback-backup --include-namespaces production

# Restore on primary with reverse StorageClass mapping
velero restore create failback-restore \
  --from-backup failback-backup \
  --storage-class-mappings gp3-csi-kms=managed-csi
```

---

## Step 3: Verify Primary Data

- [ ] Row counts match critical tables
- [ ] Sample transaction replay succeeds in staging namespace
- [ ] Secrets available via ESO on primary

---

## Step 4: GitOps on Primary

Confirm Argo CD Applications on primary cluster show `Synced` / `Healthy`:

```bash
oc config use-context <primary-cluster>
oc get applications -n openshift-gitops
```

---

## Step 5: Traffic Cutover to Primary

Reverse DNS / global LB changes from [Traffic Steering Guide](./traffic-steering-guide.md):

| Record | Before (DR active) | After (primary restored) |
|--------|-------------------|--------------------------|
| `app.example.com` | DR ingress / LB | Primary ingress / LB |

Wait for DNS TTL propagation before declaring complete.

---

## Step 6: Re-Establish DR Replication

Restore **primary → DR** direction:

- PostgreSQL: drop reverse subscription; recreate forward subscription on DR
- OADP: resume backup schedule on primary to shared S3
- Object sync: reverse rclone direction if used

---

## Step 7: Return DR to Standby

| Tier | Action |
|------|--------|
| Cold | Optionally destroy DR cluster; retain IaC templates |
| Pilot Light | Scale workers down; scale apps to 0 |
| Active/Passive | Keep full cluster; stop receiving traffic |
| Active/Active | Re-enable both regions in global LB |

---

## Step 8: Smoke Tests on Primary

- [ ] Application health 200
- [ ] Entra ID login
- [ ] Write path tested
- [ ] Monitoring alerts on primary
- [ ] OADP backup job succeeds post-failback

---

## Metrics

| Metric | Target | Actual |
|--------|--------|--------|
| Failback RTO | | |
| Data loss (RPO) | | |
| DNS propagation time | | |

Update [DR Test Results Template](./dr-test-results-template.md).

---

## Abort Failback

If primary fails validation during failback:

1. Resume DR traffic (revert DNS)
2. Re-enable writes on DR
3. Document blockers; do not force cutover
