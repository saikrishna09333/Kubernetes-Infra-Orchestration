provider "openstack" {
  user_name = "${var.openstack_user_name}"
  tenant_name = "${var.openstack_tenant_name}"
  password  = "${var.openstack_password}"
  auth_url  = "${var.openstack_auth_url}"
  insecure = "true"
}

resource "openstack_compute_secgroup_v2" "securitygroup" {
  count = "${length(var.component_name)}"
  name = "${var.prefix}-SG-${lookup(var.component_name, count.index)}"
  description = "Security group for the ${var.prefix} ${lookup(var.component_name, count.index)} instances"
  
  rule {
    from_port   = 1
    to_port     = 65535
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port = 1
    to_port = 65535
    ip_protocol = "tcp"
    cidr = "::/0"
  }
  rule {
    from_port = 53
    to_port = 53
    ip_protocol = "udp"
    cidr = "0.0.0.0/0"
  }
}

resource "openstack_compute_keypair_v2" "keypair" {
  name = "${var.prefix}-Key"
}

resource "local_file" "private-key" {
    content     = "${openstack_compute_keypair_v2.keypair.private_key }"
    filename = "${path.module}/${var.prefix}-Key.pem"
    provisioner "local-exec" {
        command = "chmod 600 ${path.module}/${var.prefix}-Key.pem"
    }
}

resource "openstack_compute_instance_v2" "MasterInstance" {
  count = "${var.master_cluster_size}"
  name  = "${var.prefix}-VM-${lookup(var.component_name, 0)}-${count.index + 1}"
  flavor_name = "${var.flavor}"
  key_pair = "${openstack_compute_keypair_v2.keypair.name}"
  security_groups = ["${var.prefix}-SG-${lookup(var.component_name, 0)}"]
  image_name = "${var.image}"
  network {
    name = "${var.network}"
  }
  block_device {
    uuid		  = "${var.image_id}"
    source_type           = "image"
    volume_size           = "${var.master_root_volume}"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }
}

resource "openstack_compute_instance_v2" "EtcdInstance" {
  count = "${var.etcd_cluster_size}"
  name  = "${var.prefix}-VM-${lookup(var.component_name, 2)}-${count.index + 1}"
  flavor_name = "${var.flavor}"
  key_pair = "${openstack_compute_keypair_v2.keypair.name}"
  security_groups = ["${var.prefix}-SG-${lookup(var.component_name, 2)}"]
  image_name = "${var.image}"
  network {
    name = "${var.network}"
  }
  block_device {
    uuid                  = "${var.image_id}"
    source_type           = "image"
    volume_size           = "${var.etcd_root_volume}"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }
}

resource "openstack_compute_instance_v2" "NodeInstance" {
  count = "${var.node_cluster_size}"
  name  = "${var.prefix}-VM-${lookup(var.component_name, 1)}-${count.index + 1}"
  flavor_name = "${var.flavor}"
  key_pair = "${openstack_compute_keypair_v2.keypair.name}"
  security_groups = ["${var.prefix}-SG-${lookup(var.component_name, 1)}"]
  image_name = "${var.image}"
  network {
    name = "${var.network}"
  }
  block_device {
    uuid                  = "${var.image_id}"
    source_type           = "image"
    volume_size           = "${var.node_root_volume}"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }
}

resource "openstack_networking_floatingip_v2" "master_floating_ip" {
  count = "${var.master_cluster_size}"
  pool = "${var.flotingip_pool}"
}

resource "openstack_networking_floatingip_v2" "node_floating_ip" {
  count = "${var.node_cluster_size}"
  pool = "${var.flotingip_pool}"
}

resource "openstack_networking_floatingip_v2" "etcd_floating_ip" {
  count = "${var.etcd_cluster_size}"
  pool = "${var.flotingip_pool}"
}


resource "openstack_compute_floatingip_associate_v2" "master_floting_ip" {
  count = "${var.master_cluster_size}"
  floating_ip = "${element(openstack_networking_floatingip_v2.master_floating_ip.*.address, count.index)}"
  instance_id = "${element(openstack_compute_instance_v2.MasterInstance.*.id, count.index)}"
}

resource "openstack_compute_floatingip_associate_v2" "node_floting_ip" {
  count = "${var.node_cluster_size}"
  floating_ip = "${element(openstack_networking_floatingip_v2.node_floating_ip.*.address, count.index)}"
  instance_id = "${element(openstack_compute_instance_v2.NodeInstance.*.id, count.index)}"
}

resource "openstack_compute_floatingip_associate_v2" "etcd_floting_ip" {
  count = "${var.etcd_cluster_size}"
  floating_ip = "${element(openstack_networking_floatingip_v2.etcd_floating_ip.*.address, count.index)}"
  instance_id = "${element(openstack_compute_instance_v2.EtcdInstance.*.id, count.index)}"
}

output "master" {
  value = "${openstack_compute_instance_v2.MasterInstance.*.access_ip_v4}"
}

output "node" {
  value = "${openstack_compute_instance_v2.NodeInstance.*.access_ip_v4}"
}

output "etcd" {
  value = "${openstack_compute_instance_v2.EtcdInstance.*.access_ip_v4}"
}
/*
output "keypair" {
  value = "${openstack_compute_keypair_v2.keypair.private_key }"
}
*/

data "template_file" "master_inventory" {
    count = "${var.master_cluster_size}"
    template = "master$${counter} ansible_host=$${ip} ip=$${ip}" 
    vars {
        ip = "${element(openstack_compute_instance_v2.MasterInstance.*.access_ip_v4, count.index)}"
        counter = "${count.index + 1}"
    }
}

data "template_file" "node_inventory" {
    count = "${var.node_cluster_size}"
    template = "node$${counter} ansible_host=$${ip} ip=$${ip}"
    vars {
        ip = "${element(openstack_compute_instance_v2.NodeInstance.*.access_ip_v4, count.index)}"
        counter = "${count.index + 1}"
    }
}

data "template_file" "etcd_inventory" {
    count = "${var.etcd_cluster_size}"
    template = "etcd$${counter} ansible_host=$${ip} ip=$${ip}"
    vars {
        ip = "${element(openstack_compute_instance_v2.EtcdInstance.*.access_ip_v4, count.index)}"
        counter = "${count.index + 1}"
    }
}

data "template_file" "ansible_inventory" {
    template = "${file("inventory.tpl")}"
    vars {
        master_ip = "${join("\n", data.template_file.master_inventory.*.rendered)}" 
        node_ip = "${join("\n", data.template_file.node_inventory.*.rendered)}" 
        etcd_ip = "${join("\n", data.template_file.etcd_inventory.*.rendered)}" 
        key_path  = "${local_file.private-key.filename}"
    }
}

resource "null_resource" "update_inventory" {
    triggers {
        template = "${data.template_file.ansible_inventory.rendered}"
    }
    provisioner "local-exec" {
        command = "echo '${data.template_file.ansible_inventory.rendered}' > ../../inventory"
    }
}
