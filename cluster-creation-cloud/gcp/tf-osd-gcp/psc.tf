
resource "google_compute_subnetwork" "psc_subnet" {
  count         = var.osd_gcp_private && var.osd_gcp_psc ? 1 : 0
  name          = "${var.clustername}-psc-subnet"
  ip_cidr_range = var.psc_subnet_cidr_block 
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
  purpose       = "PRIVATE_SERVICE_CONNECT"
  project       = var.gcp_project
}

resource "google_compute_global_forwarding_rule" "psc_google_apis" {
  count                 = var.osd_gcp_private && var.osd_gcp_psc ? 1 : 0
  name                  = "pscgapis"  
  target                = "all-apis"
  network               = google_compute_network.vpc_network.id
  ip_address            = google_compute_global_address.psc_google_apis[0].id
  load_balancing_scheme = ""
  project               = var.gcp_project
}

resource "google_compute_global_address" "psc_google_apis" {
  count         = var.osd_gcp_private && var.osd_gcp_psc ? 1 : 0
  name          = "pscgapisip"  
  purpose       = "PRIVATE_SERVICE_CONNECT"
  address_type  = "INTERNAL"
  address       = "10.0.255.100"  # outside all subnets
  network       = google_compute_network.vpc_network.id
  project       = var.gcp_project
}

resource "google_dns_managed_zone" "psc_googleapis" {
  count       = var.osd_gcp_private && var.osd_gcp_psc ? 1 : 0
  name        = "${var.clustername}-googleapis"
  dns_name    = "googleapis.com."
  description = "Private DNS zone for Google APIs"
  project     = var.gcp_project

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc_network.id
    }
  }
}

resource "google_dns_record_set" "psc_googleapis_a" {
  count        = var.osd_gcp_private && var.osd_gcp_psc ? 1 : 0
  name         = "*.${google_dns_managed_zone.psc_googleapis[0].dns_name}"
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.psc_googleapis[0].name
  rrdatas      = [google_compute_global_address.psc_google_apis[0].address]
  project      = var.gcp_project
}

resource "google_dns_managed_zone" "psc_gcr" {
  count       = var.osd_gcp_private && var.osd_gcp_psc ? 1 : 0
  name        = "${var.clustername}-gcr"
  dns_name    = "gcr.io."
  description = "Private DNS zone for GCR"
  project     = var.gcp_project

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc_network.id
    }
  }
}

resource "google_dns_record_set" "psc_gcr_a" {
  count        = var.osd_gcp_private && var.osd_gcp_psc ? 1 : 0
  name         = "*.${google_dns_managed_zone.psc_gcr[0].dns_name}"
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.psc_gcr[0].name
  rrdatas      = [google_compute_global_address.psc_google_apis[0].address]
  project      = var.gcp_project
}