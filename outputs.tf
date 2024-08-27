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

output "_05_prefix_for_resource_names_and_owner_tag" {
  value = "${var.name_prefix}"
}

output "_10_suffix_for_resource_names" {
  value = "${local.random_suffix}"
}

output "_15_gateway_external_ip" {
  value = google_compute_instance.gw_server.network_interface.0.access_config.0.nat_ip
}

output "_20_gatewaw_internal_ip" {
  value = google_compute_instance.gw_server.network_interface.0.network_ip
}

output "_25_target_internal_ip" {
  value = google_compute_instance.target_server.network_interface.0.network_ip
}

output "_30_user_name" {
  value="u${local.random_suffix}"
}

output "_35_group_name" {
  value="g${local.random_suffix}"
}
