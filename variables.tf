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

variable "name_prefix" {
  description = "A prefix for resource names and the owner tag for StrongDM"
  type = string
}

variable "project_id" {
  description = "The Google Cloud project ID to use for the API project"
  type = string
}

variable "region" {
  description = "The Google Cloud region to use"
  type = string
  default = "us-central1"
}

variable "zone" {
  description = "The Google Cloud zone to use"
  type = string
  default = "us-central1-a"
}

variable "compute_image" {
  description = "The image project and family for instance builds"
  type = string
  default = "ubuntu-os-cloud/ubuntu-2204-lts"
}

variable "iam_role_binding_duration" {
  description = "Time to delay after IAM bindings to before creating instance"
  type = string
  default = "180s"
}

variable "sdm_user_ids" {
  description = "StrongDM user ids (account ids)"
  type = list(string)
}

variable "sdm_api_access_key" {
  description = "StrongDM API access key"
  type = string
}

variable "sdm_api_secret_key" {
  description = "StrongDM API secret key"
  type = string
}

