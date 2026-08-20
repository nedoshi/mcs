# DR Drill Checklist — Cross-Cloud (ARO ↔ ROSA HCP)

Use for **monthly** backup restore tests and **quarterly** full failover drills. Record results in [DR Test Results Template](./dr-test-results-template.md).

**Automated monthly test:** [DR Validation Guide](./dr-validation-guide.md) — run `./scripts/run-dr-validation.sh`

---

## Drill Metadata

| Field | Value |
|-------|-------|
| Drill date | |
| Drill type | ☐ Backup restore · ☐ Tabletop · ☐ Full failover · ☐ Failback |
| Primary cloud | ☐ ARO · ☐ ROSA |
| DR cloud | ☐ ROSA · ☐ ARO |
| DR tier tested | ☐ Cold · ☐ Pilot · ☐ Passive · ☐ Active/Active |
| Facilitator | |
| Participants | |

---

## Monthly: Backup Restore Test (Non-Prod or DR Cluster)

- [ ] Trigger OADP backup from primary cluster
- [ ] Confirm backup completes (`velero backup describe`)
- [ ] Restore to DR cluster with StorageClass mapping
- [ ] Verify restored pods reach Running
- [ ] Verify application data integrity (spot check)
- [ ] Record restore duration: ______ minutes
- [ ] Compare to RTO target: ☐ Pass ☐ Fail

---

## Quarterly: Full Failover Drill

### Pre-Drill

- [ ] Stakeholders notified (no production impact if using DR standby)
- [ ] Runbook printed / accessible offline
- [ ] War room bridge open
- [ ] **Start time recorded** (UTC): ____________

### Execution (follow [Failover Runbook](./failover-runbook-aro-rosa.md))

- [ ] Disaster declared (simulated)
- [ ] Data promotion / OADP restore completed
- [ ] DR cluster scaled (if Pilot Light)
- [ ] GitOps sync verified on DR
- [ ] DNS / global LB cutover executed
- [ ] Smoke tests passed (login, read, write)
- [ ] **End time recorded** (UTC): ____________

### Metrics

| Metric | Target | Actual | Pass |
|--------|--------|--------|------|
| RTO (declare → smoke pass) | | | ☐ |
| RPO (simulated data loss window) | | | ☐ |
| DNS propagation | | | ☐ |

### Post-Drill

- [ ] Failback executed or scheduled — [Failback Runbook](./failback-runbook-aro-rosa.md)
- [ ] Primary → DR replication re-established
- [ ] Retrospective completed; runbook gaps documented
- [ ] Results filed in [DR Test Results Template](./dr-test-results-template.md)

---

## Annual: Failback Drill

- [ ] Failback runbook executed end-to-end
- [ ] Traffic restored to primary
- [ ] DR returned to standby mode
- [ ] Failback RTO measured: ______ minutes

---

## Tabletop Exercise (Twice Yearly)

Walk through runbooks without executing cutover:

- [ ] Disaster declaration authority confirmed
- [ ] Communication plan exercised
- [ ] Recovery sequencing validated
- [ ] Gap list produced with owners and dates

---

## Sign-Off

| Role | Name | Date |
|------|------|------|
| SRE Lead | | |
| Cloud Architect | | |
| App Owner | | |
