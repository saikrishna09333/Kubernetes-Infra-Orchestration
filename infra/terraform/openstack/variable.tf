variable "openstack_user_name" {}
variable "openstack_tenant_name" {}
variable "openstack_password" {}
variable "openstack_auth_url" {}
variable "image" {}
variable "flavor" {}
variable "network" {}
variable "master_cluster_size" {}
variable "etcd_cluster_size" { default = "0" }
variable "node_cluster_size" {}
variable "master_root_volume" { default = "30" }
variable "node_root_volume" { default = "50" }
variable "etcd_root_volume" { default = "30" }
variable "prefix" { default  = "K8S" }
variable "image_id" {}
variable "counter" { default = "1" }
variable "flotingip_pool" {}

variable "component_name" {
  default = {
    "0" = "Master"
    "1" = "Node"
    "2" = "Etcd"
   }
}

