# Copyright 2023 Google LLC
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Enable APIs

resource "google_project_service" "compute_engine_service" {
  provider = google

  service = "compute.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy = false
}

resource "google_project_service" "service_networking_service" {
  provider = google

  service = "servicenetworking.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy = false
}

# Create a four-byte (eight hex digit) random suffix to make Google resource
# names unique.

resource "random_id" rand {
  byte_length = 4
}

locals {
  random_suffix = lower(random_id.rand.hex)
}

# Set up the VPC network and subnet resources

resource "google_compute_network" "vpc_network" {
  provider = google

  name = "vpc-${local.random_suffix}"
  auto_create_subnetworks = false

  depends_on = [
    google_project_service.compute_engine_service
  ]
}

resource "google_compute_subnetwork" "public_subnet" {
  provider = google

  name = "public-subnet-${local.random_suffix}"
  ip_cidr_range = "10.10.1.0/24"
  network = google_compute_network.vpc_network.id
  region = var.region
}

# Create Service Accounts

resource "google_service_account" "strongdm_gw_sa" {
  provider = google

  account_id = "gw-sa-${local.random_suffix}"
  description = "StrongDM Gateway Service Account"
}

resource "google_service_account" "strongdm_target_sa" {
  provider = google

  account_id = "target-sa-${local.random_suffix}"
  description = "Target Service Account"
}

# Firewall rules

resource "google_compute_firewall" "iap_allow_ssh" {
  provider = google

  name = "allow-iap-ssh-${local.random_suffix}"
  description = "Allow IAP SSH traffic to instances"

  network = google_compute_network.vpc_network.name
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports = ["22"]
  }

  source_ranges = [ "35.235.240.0/20" ]
}

resource "google_compute_firewall" "allow_strongdm_gw" {
  provider = google

  name = "allow-strongdm-gw-${local.random_suffix}"
  description = "Allow StrongDM traffic to gateways"

  network = google_compute_network.vpc_network.name
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports = ["5000"]
  }

  source_ranges = [ "0.0.0.0/0" ]
  target_service_accounts = [ google_service_account.strongdm_gw_sa.email ]
}

resource "google_compute_firewall" "allow_strongdmgw_to_target" {
  provider = google

  name = "allow-strongdm-target-${local.random_suffix}"
  description = "Allow ssh from StrongDM to target"

  network = google_compute_network.vpc_network.name
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports = ["22"]
  }

  source_service_accounts=[ google_service_account.strongdm_gw_sa.email ]
  target_service_accounts=[ google_service_account.strongdm_target_sa.email ]
}

# Set up the NAT gateway and cloud router

resource "google_compute_router" "router" {
  provider = google

  name = "nat-router-${local.random_suffix}"
  network = google_compute_network.vpc_network.id
  region = var.region
}

resource "google_compute_router_nat" "nat" {
  provider = google

  name = "nat-${local.random_suffix}"
  router = google_compute_router.router.name
  region = var.region
  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips = google_compute_address.nat_external_ip.*.self_link
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Define static IPs

resource "google_compute_address" "gw_external_ip" {
  name = "gw-ext-${local.random_suffix}"
  description = "External IP for StrongDM gateway"
}

resource "google_compute_address" "gw_internal_ip" {
  name = "gw-int-${local.random_suffix}"
  subnetwork  = google_compute_subnetwork.public_subnet.id
  address_type = "INTERNAL"
  region = "us-central1"
}

resource "google_compute_address" "target_internal_ip" {
  name = "target-int-${local.random_suffix}"
  subnetwork  = google_compute_subnetwork.public_subnet.id
  address_type = "INTERNAL"
  region = "us-central1"
}

resource "google_compute_address" "nat_external_ip" {
  count = 1
  name = "nat-ext-${count.index}-${local.random_suffix}"
  description = "External IP for NAT gateway"
}

# Register StrongDM gateway

resource "sdm_node" "gw" {
  gateway {
    name = "jslevine-gw-${local.random_suffix}"
    listen_address="${google_compute_address.gw_external_ip.address}:5000"
  }
}

# Set up the StrongDM gateway instance
#
# Use depends_on to wait for the NAT gateway go be available so the
# startup script can download packages.

resource "google_compute_instance" "gw_server" {
  provider = google

  name = "strongdm-gw-${local.random_suffix}"

  boot_disk {
    initialize_params {
      image = var.compute_image
    }
  }

  machine_type = "e2-medium"

  metadata = {
    enable-oslogin = "TRUE"
    shutdown-script = templatefile(
      "${path.module}/etc/gw-shutdown-script",
      {
        instance_name="strongdm-gw-${local.random_suffix}"
        instance_zone="${var.zone}"
      }
    )
    startup-script = templatefile(
      "${path.module}/etc/gw-startup-script",
      {
        instance_name="strongdm-gw-${local.random_suffix}"
        instance_zone="${var.zone}"
        sdm_token=sdm_node.gw.gateway[0].token
      }
    )
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public_subnet.self_link
    network_ip = google_compute_address.gw_internal_ip.address
    access_config {
      nat_ip = google_compute_address.gw_external_ip.address
    }
  }

  service_account {
    email  = google_service_account.strongdm_gw_sa.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot = true
    enable_vtpm = true
    enable_integrity_monitoring = true
  }

  zone = var.zone
}

# Set up the StrongDM target instance
#
# Use depends_on to wait for the NAT gateway go be available so the
# startup script can download packages.

resource "google_compute_instance" "target_server" {
  provider = google

  name = "strongdm-target-${local.random_suffix}"

  boot_disk {
    initialize_params {
      image = var.compute_image
    }
  }

  machine_type = "e2-medium"

  metadata = {
    enable-oslogin = "TRUE"
    shutdown-script = templatefile(
      "${path.module}/etc/target-shutdown-script",
      {
        instance_name="strongdm-target-${local.random_suffix}"
        instance_zone="${var.zone}"
      }
    )
    startup-script = templatefile(
      "${path.module}/etc/target-startup-script",
      {
        instance_name="strongdm-target-${local.random_suffix}"
        instance_zone="${var.zone}"
      }
    )
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public_subnet.self_link
    network_ip = google_compute_address.target_internal_ip.address
  }

  service_account {
    email  = google_service_account.strongdm_target_sa.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot = true
    enable_vtpm = true
    enable_integrity_monitoring = true
  }

  zone = var.zone
}

#resource "terraform_data" "gw_server_wait_chromeremotedesktop" {
#  provisioner "local-exec" {
#    command = "${path.module}/etc/waitforlabel-script"
#
#    environment = {
#      INSTANCE_NAME="ubuntu-server-${local.random_suffix}"
#      ZONE="us-central1-a"
#      LABEL_KEY="crdcompleted"
#      LABEL_VALUE="true"
#      WAIT_MESSAGE="Installing Chrome Remote Desktop"
#    }
#  }
#
#  depends_on = [
#    google_compute_instance.gw_server
#  ]
#}
#
#resource "terraform_data" "gw_server_wait_xfce" {
#  provisioner "local-exec" {
#    command = "${path.module}/etc/waitforlabel-script"
#
#    environment = {
#      INSTANCE_NAME="ubuntu-server-${local.random_suffix}"
#      ZONE="us-central1-a"
#      LABEL_KEY="xfcecompleted"
#      LABEL_VALUE="true"
#      WAIT_MESSAGE="Installing Xfce"
#    }
#  }
#
#  depends_on = [
#    terraform_data.gw_server_wait_chromeremotedesktop
#  ]
#}
#
#resource "terraform_data" "the_end_wait_chrome" {
#  provisioner "local-exec" {
#    command = "${path.module}/etc/waitforlabel-script"
#
#    environment = {
#      INSTANCE_NAME="ubuntu-server-${local.random_suffix}"
#      ZONE="us-central1-a"
#      LABEL_KEY="chromecompleted"
#      LABEL_VALUE="true"
#      WAIT_MESSAGE="Installing Chrome browser"
#    }
#  }
#
#  depends_on = [
#    terraform_data.gw_server_wait_xfce
#  ]
#}
