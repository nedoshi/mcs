# firewall rules for PSC

resource "google_compute_firewall" "psc_allow_https" {
  count    = var.osd_gcp_psc ? 1 : 0
  name     = "${var.clustername}-psc-allow-https"
  network  = google_compute_network.vpc_network.id
  project  = var.gcp_project
  priority = 1000

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_ranges = [
    var.master_cidr_block,
    var.worker_cidr_block
  ]
  
  destination_ranges = [var.psc_subnet_cidr_block]
  
  direction = "INGRESS"
}

resource "google_compute_firewall" "psc_allow_dns" {
  count    = var.osd_gcp_psc ? 1 : 0
  name     = "${var.clustername}-psc-allow-dns"
  network  = google_compute_network.vpc_network.id
  project  = var.gcp_project
  priority = 1000

  allow {
    protocol = "tcp"
    ports    = ["53"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["53"]
  }

  source_ranges = [
    var.master_cidr_block,
    var.worker_cidr_block
  ]
  
  direction = "INGRESS"
}

resource "google_compute_firewall" "psc_internal_all" {
  count    = var.osd_gcp_psc ? 1 : 0
  name     = "${var.clustername}-psc-internal-all"
  network  = google_compute_network.vpc_network.id
  project  = var.gcp_project
  priority = 900

  allow {
    protocol = "all"
  }

  source_ranges = [
    var.master_cidr_block,
    var.worker_cidr_block,
    var.psc_subnet_cidr_block
  ]
  
  direction = "INGRESS"
}

# uses IP ranges instead of tags to avoid mismatch with OSD-created instances
resource "google_compute_firewall" "bastion_to_cluster" {
  count    = var.enable_osd_gcp_bastion && var.osd_gcp_private ? 1 : 0
  name     = "${var.clustername}-bastion-to-cluster"
  network  = google_compute_network.vpc_network.id
  project  = var.gcp_project
  priority = 1000

  allow {
    protocol = "tcp"
    ports    = ["6443", "22623", "443", "80"]
  }

  source_ranges = [var.bastion_cidr_block]
  
  destination_ranges = [
    var.master_cidr_block,
    var.worker_cidr_block
  ]
  
  direction = "INGRESS"
  
}

# additional rule for cluster internal communication
resource "google_compute_firewall" "cluster_internal" {
  count    = var.osd_gcp_private ? 1 : 0
  name     = "${var.clustername}-cluster-internal"
  network  = google_compute_network.vpc_network.id
  project  = var.gcp_project
  priority = 900

  allow {
    protocol = "all"
  }

  # allow all communication between master and worker nodes
  source_ranges = [
    var.master_cidr_block,
    var.worker_cidr_block
  ]
  
  destination_ranges = [
    var.master_cidr_block,
    var.worker_cidr_block
  ]
  
  direction = "INGRESS"
}