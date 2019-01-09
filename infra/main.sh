#!/usr/bin/env bash
  
red=$'\e[1;31m'
blue=$'\e[1;34m'
end=$'\e[0m'

terraform_base='terraform/openstack'
var_file="$terraform_base/terraform.tfvars"

dir=`pwd`

pre_install(){
  echo "${blue}Please provide the http proxy url: ${end}"
  read -i http://10.144.106.132:8678 -e proxy_url
  #export http_proxy=$proxy_url
  #terraform init $terraform_base
  sudo pip install -r kubespray/requirements.txt --proxy $proxy_url
  #unset http_proxy
  sed -i "$ a http_proxy: $proxy_url" kubespray/inventory/local/group_vars/all/all.yml
  sed -i "$ a https_proxy: $proxy_url" kubespray/inventory/local/group_vars/all/all.yml
}

cloud_credentials(){
  echo "${blue}Please enter your OpenStack Auth URL: ${end}"
  read -i https://10.157.11.80:5000/v3 -e openstack_auth_url
  echo openstack_auth_url = \"$openstack_auth_url\" > $var_file

  echo "${blue}Please enter your OpenStack Project/Tenant Name: ${end}"
  read -i Jiocloud-NonProduction -e openstack_tenant_name
  echo openstack_tenant_name = \"$openstack_tenant_name\" >> $var_file

  echo "${blue}Please enter your OpenStack UserName: ${end}"
  read -i anubhav.kumar -e openstack_user_name
  echo openstack_user_name = \"$openstack_user_name\" >> $var_file

  echo "${blue}Please enter your OpenStack Password: ${end}"
  read  -i anu@2301 -es openstack_password
  echo "$openstack_password" | tr -c \\n \*
  echo openstack_password = \"$openstack_password\" >> $var_file
}

cluster_req(){

  echo "${blue}Please provide the Image name: ${end}"
  read -i RHEL-7.5 -e image
  echo image = \"$image\" >> $var_file

  echo "${blue}Please provide the Image Id: ${end}"
  read -i 8148a80c-8171-4e01-ad6e-97fbbe605a31 -e image_id
  echo image_id = \"$image_id\" >> $var_file

  echo "${blue}Please provide the Flavor name: ${end}"
  read -i m1.large -e flavor
  echo flavor = \"$flavor\" >> $var_file

  echo "${blue}Please provide the Network name: ${end}"
  read -i JC_NP_Network_19  -e network
  echo network = \"$network\" >> $var_file

  echo "${blue}Please provide the Floting IP Pool: ${end}"
  read -i ext-net-nonprod2  -e flotingip_pool
  echo flotingip_pool = \"$flotingip_pool\" >> $var_file

  echo "${blue}Please provide Cluster size for Master (1/3): ${end}"
  read -e master_cluster_size
  case $master_cluster_size in
  1|3)
    echo master_cluster_size = \"$master_cluster_size\" >> $var_file
    ;;
  *)
    echo "${red}Wrong selection...Exiting.${end}"
    exit 1
    ;;
  esac

  echo "${blue}Please provide Cluster size for Etcd (1/3/5): ${end}"
  read -e etcd_cluster_size
  case $etcd_cluster_size in
  1|3|5)
    echo etcd_cluster_size = \"$etcd_cluster_size\" >> $var_file
    ;;
  *)
    echo "${red}Wrong selection...Exiting.${end}"
    exit 1
    ;;
  esac

  echo "${blue}Please provide worker node count (Only Integer): ${end}"
  read -e node_cluster_size
  if [[ ! "$node_cluster_size" =~ ^[1-9]+[0-9]*$ ]] ; then
    echo "Sorry integers only"
    exit 1
  fi
  echo node_cluster_size = \"$node_cluster_size\" >> $var_file
  
}

if [ ! -f $terraform_base/terraform.tfplan ] ; then
    pre_install
    cloud_credentials
    cluster_req
fi

cd $terraform_base
terraform plan -var-file=terraform.tfvars -out terraform.tfplan

terraform apply terraform.tfplan
if [ $? -ne 0 ] ; then
   echo -e "\n${red}Error in provisioning. Exiting..!${end}"
   exit 1
fi

cd $dir

echo "${blue}Pausing for 10 seconds${end}"
sleep 10

export ANSIBLE_HOST_KEY_CHECKING=False
ansible all -m ping -i inventory

ansible-playbook -i inventory -b --become-user=root ansible/basic.yaml

cp inventory kubespray/inventory/local/

ansible-playbook -i kubespray/inventory/local/inventory --become --become-user=root kubespray/cluster.yml
