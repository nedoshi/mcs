# Hardware Recommendations for OpenShift Home Lab

Comprehensive guide for selecting hardware for your OpenShift home lab.

## Minimum Requirements

### Single Node OpenShift (SNO)
- **CPU**: 8 vCPU (4 physical cores with hyperthreading)
- **RAM**: 32GB (16GB absolute minimum, not recommended)
- **Storage**: 120GB SSD minimum
- **Network**: 1 Gbps Ethernet

### Compact Cluster (3 Control Plane Nodes)
- **Per Node**:
  - CPU: 8 vCPU
  - RAM: 32GB
  - Storage: 120GB SSD
- **Total**: 24 vCPU, 96GB RAM, 360GB storage

### Full Cluster (3 Control Plane + 2 Workers)
- **Control Plane** (per node): 8 vCPU, 16GB RAM, 100GB SSD
- **Worker** (per node): 8+ vCPU, 32GB+ RAM, 200GB+ SSD
- **Total**: 40+ vCPU, 112+ GB RAM, 700+ GB storage

## Recommended Hardware by Budget

### Budget: $300-500 (Single Node)

#### Option 1: Lenovo ThinkCentre M910 Tiny (Refurbished)
- **Price**: ~$280-400
- **CPU**: Intel i7-7700T (4 cores, 8 threads @ 2.9GHz)
- **RAM**: 32GB DDR4 (upgradeable to 64GB)
- **Storage**: 256GB NVMe SSD
- **Form Factor**: 1.3L ultra-compact
- **Power**: ~65W TDP
- **Where to Buy**: eBay, NewEgg, Amazon Renewed

**Pros**: Tiny footprint, quiet, low power, excellent value
**Cons**: Limited to 64GB RAM max, older CPU

#### Option 2: Dell OptiPlex 7060 Micro (Refurbished)
- **Price**: ~$350-450
- **CPU**: Intel i7-8700T (6 cores, 12 threads @ 2.4GHz)
- **RAM**: 32GB DDR4
- **Storage**: 512GB NVMe SSD
- **Power**: ~65W TDP

**Pros**: Newer CPU, more cores, still compact
**Cons**: Slightly larger than ThinkCentre

### Mid-Range: $600-1000

#### Option 1: Intel NUC 10i7FNK
- **Price**: ~$600-800 (barebones + RAM + SSD)
- **CPU**: Intel i7-10710U (6 cores, 12 threads @ 1.1-4.7GHz)
- **RAM**: Up to 64GB DDR4 SODIMM (2x32GB)
- **Storage**: 2x M.2 NVMe slots (up to 2TB each)
- **Power**: 25W TDP
- **Networking**: 1Gbps Ethernet

**Pros**: Latest gen CPU, dual NVMe, very efficient
**Cons**: More expensive, sodimm RAM

#### Option 2: HP EliteDesk 800 G5 Mini
- **Price**: ~$500-700 (refurbished)
- **CPU**: Intel i7-9700 (8 cores, 8 threads @ 3.0GHz)
- **RAM**: Expandable to 64GB DDR4
- **Storage**: M.2 NVMe + 2.5" SATA bay
- **Power**: ~65W

**Pros**: Full desktop CPU, good expansion, reliable
**Cons**: No hyperthreading on this model

### Advanced: $1000-2000 (Multi-Node Cluster)

#### Option 1: 3x Mini PCs (Cluster in Miniature)
- **Total**: ~$1200-1500
- **Nodes**: 3x Lenovo ThinkCentre M910 Tiny or similar
- **Setup**: 3-node compact cluster
- **Power**: ~200W total
- **Footprint**: Desktop drawer size

**Pros**: True multi-node testing, low power, quiet, compact
**Cons**: Limited RAM per node, harder to expand

#### Option 2: Single Server - Dell PowerEdge R720xd
- **Price**: ~$400-800 (used)
- **CPU**: Dual Xeon E5-2670v2 (10 cores each = 40 threads total)
- **RAM**: 128-256GB ECC DDR3
- **Storage**: 12x 3.5" bays + 2x 2.5" rear bays
- **Power**: ~400-600W
- **Rack**: 2U rackmount

**Pros**: Massive capacity, run entire cluster in VMs, ECC RAM
**Cons**: Loud, power-hungry, rack required, older platform

#### Option 3: Single Server - HP ProLiant DL380 Gen9
- **Price**: ~$600-1000 (used)
- **CPU**: Dual Xeon E5-2680v4 (14 cores each = 56 threads total)
- **RAM**: 256GB+ ECC DDR4
- **Storage**: 8x 2.5" or 4x 3.5" bays
- **Power**: ~500W
- **Rack**: 2U rackmount

**Pros**: Newer platform, DDR4, powerful, reliable
**Cons**: Expensive, loud, power-hungry, rack required

### Enthusiast: $2000+ (Production-Like Lab)

#### Option: Multiple Servers + Dedicated Storage
- **Compute**: 3x HP DL360 Gen9 or Gen10
- **Storage**: TrueNAS server or Synology NAS
- **Network**: Managed switches, VLANs
- **Power**: UPS system
- **Rack**: 12U-24U rack cabinet

**Use Case**: Production simulation, performance testing, large workloads

## Storage Considerations

### Boot Storage (OS + OpenShift)
- **Minimum**: 120GB SSD
- **Recommended**: 256GB NVMe SSD
- **Optimal**: 512GB+ NVMe SSD

### Persistent Storage (Applications)
- **Option 1**: Local SSDs (fastest, not HA)
- **Option 2**: NFS from NAS (good balance)
- **Option 3**: OpenShift Data Foundation/Ceph (enterprise-grade, requires 3+ nodes)

### NAS Options
- **Budget**: Raspberry Pi 4 + USB HDDs (~$150)
- **Mid-Range**: Synology DS420+ (~$500)
- **Advanced**: TrueNAS build (~$800-1500)

## Network Hardware

### Minimum
- **Router**: Any home router with admin access
- **Switch**: Built-in router switch ports
- **Cables**: Cat5e or Cat6 Ethernet

### Recommended
- **Router**: pfSense/OPNsense or UniFi Dream Machine
- **Switch**: Managed gigabit switch (8-24 ports)
- **Cables**: Cat6 Ethernet cables
- **Optional**: Separate VLAN for lab network

### Advanced
- **Router**: pfSense on dedicated hardware
- **Switch**: Managed 10Gbps switch
- **Cables**: Cat6a or Cat7
- **Network**: Multiple VLANs, Link Aggregation

## Power Considerations

### Power Consumption Estimates

| Configuration | Idle | Load | Monthly Cost (@ $0.12/kWh) |
|--------------|------|------|---------------------------|
| Single Mini PC | 15W | 45W | $3-5 |
| 3x Mini PCs | 45W | 135W | $10-15 |
| 1x Server (R720) | 150W | 400W | $35-50 |
| 3x Servers + NAS | 600W | 1200W | $90-150 |

### UPS Recommendations

#### Budget: APC Back-UPS 600VA (~$80)
- **Runtime**: 10-15 minutes for mini PCs
- **Use**: Graceful shutdown during outages

#### Mid-Range: CyberPower 1500VA (~$180)
- **Runtime**: 30-45 minutes for mini PCs
- **Use**: Extended runtime, network management

#### Advanced: APC Smart-UPS 3000VA (~$600+)
- **Runtime**: 1-2 hours for servers
- **Use**: Extended outages, rack mount

## Cooling and Noise

### Mini PCs
- **Noise**: Near silent (<30dB)
- **Cooling**: Passive + small fan
- **Location**: Can sit on desk

### Servers
- **Noise**: Loud (60-70dB)
- **Cooling**: High-RPM fans
- **Location**: Basement/garage/closet recommended
- **Solutions**: Sound-dampening rack, fan speed controllers

## Networking Topology

### Basic Setup
```
Internet → Router → Switch → OpenShift Nodes
```

### Advanced Setup
```
Internet
  │
  └─ pfSense/OPNsense Firewall
      │
      ├─ Management VLAN (192.168.1.0/24)
      │   └─ Bastion/Jump Host
      │
      ├─ Cluster VLAN (192.168.100.0/24)
      │   ├─ Control Plane Nodes
      │   └─ Worker Nodes
      │
      └─ Storage VLAN (192.168.200.0/24)
          └─ NAS/Storage Nodes
```

## Expansion Path

### Start Small, Grow Big

1. **Phase 1: Single Node** ($300-600)
   - 1x Mini PC for SNO
   - Learn OpenShift basics
   - Run lightweight workloads

2. **Phase 2: Add Storage** (+$200-500)
   - NAS for persistent volumes
   - Backup target
   - Media server

3. **Phase 3: Add Nodes** (+$600-1200)
   - 2 more mini PCs
   - Form 3-node cluster
   - Test HA scenarios

4. **Phase 4: Dedicated Services** (+$200-400)
   - Separate DNS/DHCP server
   - Dedicated jump host
   - Monitoring server

## Buying Tips

### Where to Buy
- **New**: NewEgg, Amazon, B&H Photo
- **Refurbished**: NewEgg Renewed, Amazon Renewed, eBay
- **Used**: eBay, r/homelabsales, Facebook Marketplace, Craigslist

### What to Look For
- **Warranty**: At least 90-day warranty for refurb
- **Seller Rating**: 98%+ positive
- **Return Policy**: 30+ days
- **Generation**: i7 7th gen or newer (Kaby Lake+)

### What to Avoid
- **Very Old CPUs**: Pre-Haswell (4th gen)
- **No Hyperthreading**: Limits vCPU count
- **Limited RAM**: Max RAM < 32GB
- **No SSD**: HDD-only systems (too slow)

## Sample Configurations

### Configuration 1: "Starter Lab"
- **Budget**: $400
- **Hardware**: 1x ThinkCentre M910 Tiny (i7-7700T, 32GB RAM, 256GB SSD)
- **Network**: Home router
- **Use**: SNO, learning, development

### Configuration 2: "Serious Hobbyist"
- **Budget**: $1200
- **Hardware**:
  - 3x ThinkCentre M910 Tiny
  - 1x Synology DS220+ (2-bay NAS)
  - 1x Netgear GS308E managed switch
- **Network**: VLANs for segmentation
- **Use**: HA cluster, storage, production-like testing

### Configuration 3: "Home Production"
- **Budget**: $2500
- **Hardware**:
  - 3x Intel NUC 10i7 (64GB RAM each)
  - 1x TrueNAS build (6x 4TB HDDs)
  - 1x pfSense firewall (4-port NIC)
  - 1x 24-port managed switch
  - 1x APC Smart-UPS 1500VA
- **Network**: Multiple VLANs, 10Gbps backbone
- **Use**: Production workloads, GitOps, CI/CD

## Checklist Before Buying

- [ ] CPU meets minimum (8 vCPU)
- [ ] RAM meets minimum (32GB for SNO)
- [ ] SSD storage (not HDD)
- [ ] Gigabit Ethernet
- [ ] Acceptable noise level for location
- [ ] Power consumption fits budget
- [ ] Expansion options (RAM, storage)
- [ ] Warranty/return policy acceptable
- [ ] Price matches budget
- [ ] All components available

## Next Steps

1. Choose your budget tier
2. Select hardware configuration
3. Order hardware
4. While waiting, set up network infrastructure
5. Prepare installation media
6. Follow [Installation Walkthrough](installation-walkthrough.md)
