# Storage Options for OpenShift

Comprehensive guides and reference materials for storage solutions across Red Hat OpenShift platforms including ROSA (AWS), ARO (Azure), and OpenShift Virtualization.

## 📚 Documentation

- **[Documentation Index](Index.md)** - Complete table of contents and navigation guide
- **[OpenShift Storage Guide](openshift_storage_guide.md)** - Complete setup guide for ROSA and ARO storage
- **[ARO Storage Guide](aro_storage_guide.md)** - Comprehensive beginner's guide to ARO storage
- **[ARO Backup & Restore](aro_backup_restore.md)** - Cross-cluster backup and restore with OADP (Velero)
- **[Storage Vendor Solutions](storage_vendor_openshift_support.md)** - Enterprise storage vendor solutions

## 📝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to contribute to this documentation.

## 📋 Changelog

See [CHANGELOG.md](CHANGELOG.md) for a detailed list of changes and updates to this documentation.

## Quick Start

### For ROSA (AWS)
- **EBS GP3** - Recommended for most workloads (good performance/cost balance)
- **EFS** - Use when you need shared storage across multiple pods
- **IO2** - Consider for high-performance databases

👉 See [OpenShift Storage Guide - ROSA Section](openshift_storage_guide.md#rosa-aws-storage-setup) for detailed setup

### For ARO (Azure)
- **Azure Disk Premium** - Start here for block storage needs
- **Azure Files Premium** - Use for shared file storage
- **Azure NetApp Files** - Consider for enterprise workloads requiring high performance

👉 See [ARO Storage Guide](aro_storage_guide.md) for comprehensive guide and [OpenShift Storage Guide - ARO Section](openshift_storage_guide.md#aro-azure-storage-setup) for setup instructions

## Storage Options by Platform

### ROSA (Red Hat OpenShift Service on AWS)
- **Amazon EBS** (GP3, IO1, IO2) - Primary block storage option
- **Amazon EFS** - Shared file storage for multi-pod access
- **Amazon FSx** - High-performance file systems (Lustre, NetApp ONTAP)
- **S3** - Object storage via CSI drivers
- **Instance Store** - Ephemeral storage for temporary high-performance needs

### ARO (Azure Red Hat OpenShift)
- **Azure Disk** - Managed disk storage (Premium/Ultra SSD) for persistent volumes
- **Azure Files** - Managed file shares (SMB/NFS) for shared storage
- **Azure NetApp Files** - Enterprise-grade NFS/SMB with high performance
- **Azure Blob Storage** - Object storage for large datasets and archives

### OpenShift Virtualization
- **OpenShift Data Foundation (ODF)** - Unified block, file, and object storage with Ceph backend
- **Local Storage Operator** - Direct-attached storage scenarios
- **External Storage Providers** - Via CSI drivers (NetApp, Pure Storage, Dell EMC, etc.)
- **NFS** - Shared file storage
- **iSCSI** - Block storage

## Key Evaluation Criteria

**Performance Requirements**
- IOPS requirements for your workloads
- Throughput needs (MB/s)
- Latency sensitivity
- Storage class performance tiers (standard, premium, ultra)

**Availability and Durability**
- Replication options (zone-redundant, geo-redundant)
- Backup and snapshot capabilities
- Multi-zone deployment support
- RTO/RPO requirements

**Scalability Considerations**
- Dynamic provisioning capabilities
- Storage expansion options
- Performance scaling (can you increase IOPS independently?)
- Capacity limits and quotas

**Access Patterns**
- ReadWriteOnce (RWO) vs ReadWriteMany (RWX) requirements
- Block vs file vs object storage needs
- Shared storage requirements across pods/nodes

**Cost Optimization**
- Storage pricing models (provisioned vs consumed)
- Performance tier costs
- Snapshot and backup costs
- Data transfer charges

**Integration and Management**
- CSI driver maturity and support
- OpenShift integration quality
- Monitoring and observability features
- Automated provisioning capabilities

## Recommendation Framework

**For Production Workloads**
Look for storage solutions that offer high availability, consistent performance, enterprise-grade features, and strong backup/disaster recovery capabilities.

**For Development/Testing**
Consider cost-effective options with good performance but potentially lower availability guarantees.

**For Virtualization Workloads**
Prioritize low-latency block storage with high IOPS capability, as VMs typically have more demanding storage requirements than containerized applications.

**Compliance and Security**
Evaluate encryption at rest and in transit, access controls, audit logging, and any industry-specific compliance requirements. See the [Security Considerations](openshift_storage_guide.md#security-considerations) section in the OpenShift Storage Guide for detailed security guidance.

## Security

All guides include security considerations covering:
- Encryption at rest and in transit
- Access control and RBAC/IAM configuration
- Secret management best practices
- Network security recommendations

See the security sections in:
- [OpenShift Storage Guide - Security](openshift_storage_guide.md#security-considerations)
- [ARO Storage Guide - Security](aro_storage_guide.md#security-considerations)

## Version Compatibility

This documentation is tested and validated with:
- **OpenShift**: 4.10 - 4.14
- **ROSA**: All supported ROSA versions
- **ARO**: All supported ARO versions

See individual guides for specific version requirements and compatibility notes.

---

The choice between these options will depend heavily on your specific workload characteristics, performance requirements, budget constraints, and operational preferences. I'd recommend starting with the native cloud provider storage options for ROSA and ARO, as they typically offer the best integration and support, while for OpenShift Virtualization, ODF provides a comprehensive storage platform if you need the full spectrum of storage types.
