###############################################################################
# TERRAFORM + GOOGLE PROVIDER
###############################################################################
terraform {
  required_version = ">= 1.5.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.gcp_region
}

###############################################################################
# VARIABLES
###############################################################################
variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "weather-devops-barath01"
}

variable "gcp_region" {
  description = "GCP region (asia-south2 = Delhi)"
  type        = string
  default     = "asia-south2"
}

variable "gcp_zone_suffix" {
  description = "Zone letter inside the region for worker nodes"
  type        = string
  default     = "a"
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "terraform-gke"
}

variable "master_authorized_cidr" {
  description = "CIDR allowed to reach the public API endpoint (restrict to your IP/VPN)"
  type        = string
  default     = "0.0.0.0/0"
}

###############################################################################
# ENABLE REQUIRED APIS
###############################################################################
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])

  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

###############################################################################
# VPC & NETWORKING
###############################################################################
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "private_subnet" {
  name                     = "${var.cluster_name}-subnet"
  ip_cidr_range            = "10.0.1.0/24"
  region                   = var.gcp_region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods-range"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = "10.2.0.0/20"
  }
}

# Cloud Router + Cloud NAT: outbound internet for private nodes
resource "google_compute_router" "router" {
  name    = "${var.cluster_name}-router"
  region  = var.gcp_region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

###############################################################################
# SERVICE ACCOUNT FOR GKE NODES
###############################################################################
resource "google_service_account" "gke_sa" {
  account_id   = "${var.cluster_name}-sa"
  display_name = "Service Account for GKE Node Pool"

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "gke_roles" {
  for_each = toset([
    "roles/container.defaultNodeServiceAccount",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader"
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

###############################################################################
# GKE CLUSTER (CONTROL PLANE)
###############################################################################
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.gcp_region

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.private_subnet.id

  # Regional control plane, nodes in a single zone (keeps dev cost/quota low)
  node_locations = ["${var.gcp_region}-${var.gcp_zone_suffix}"]

  # Manage nodes via the separate node pool below
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false

  # GKE picks and upgrades supported versions
  release_channel {
    channel = "REGULAR"
  }

  # VPC-native networking
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods-range"
    services_secondary_range_name = "services-range"
  }

  # Private nodes, public API endpoint
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.master_authorized_cidr
      display_name = "allowed-admin-network"
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
  }

  resource_labels = {
    environment = "dev"
    managed_by  = "terraform"
  }

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.gke_roles
  ]
}

###############################################################################
# MANAGED NODE POOL
###############################################################################
resource "google_container_node_pool" "general" {
  name     = "general-node-pool"
  location = var.gcp_region
  cluster  = google_container_cluster.primary.name

  # Total across node_locations (single zone here)
  autoscaling {
    total_min_node_count = 1
    total_max_node_count = 3
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = "e2-medium"
    disk_size_gb = 30
    disk_type    = "pd-balanced"
    image_type   = "COS_CONTAINERD"
    spot         = false # set true for cheaper Spot VMs

    service_account = google_service_account.gke_sa.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      environment = "dev"
      nodegroup   = "general"
    }

    tags = ["${var.cluster_name}-worker", "dev"]
  }

  depends_on = [
    google_project_iam_member.gke_roles,
    google_compute_router_nat.nat
  ]
}

###############################################################################
# OUTPUTS
###############################################################################
output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "GKE API endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_version" {
  description = "Kubernetes control plane version"
  value       = google_container_cluster.primary.master_version
}

output "vpc_id" {
  description = "VPC ID"
  value       = google_compute_network.vpc.id
}

output "private_subnet" {
  description = "Private subnet ID"
  value       = google_compute_subnetwork.private_subnet.id
}

output "node_pool" {
  description = "GKE node pool name"
  value       = google_container_node_pool.general.name
}

output "get_credentials_command" {
  description = "Configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.gcp_region} --project ${var.project_id}"
}