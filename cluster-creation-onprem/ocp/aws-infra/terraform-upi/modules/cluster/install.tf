locals {
  install_dir = "${var.install_output_dir}/${var.infrastructure_name}"
  cp_count    = var.control_plane.count

  install_config = trimspace(<<-YAML
apiVersion: v1
baseDomain: ${var.base_domain}
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform:
    aws:
      type: ${var.worker.instance_type}
  replicas: ${var.use_worker_machinesets ? var.worker.count : 0}
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      type: ${var.control_plane.instance_type}
  replicas: ${var.control_plane.count}
metadata:
  name: ${var.cluster_name}
networking:
  clusterNetwork:
  - cidr: ${var.cluster_network_cidr}
    hostPrefix: ${var.cluster_network_host_prefix}
  machineNetwork:
  - cidr: ${var.vpc_cidr}
  networkType: ${var.network_type}
  serviceNetwork:
  - ${var.service_network_cidr}
platform:
  aws:
    region: ${var.region}
pullSecret: '${replace(trimspace(file(var.openshift_pull_secret_path)), "'", "''")}'
sshKey: '${var.ssh_public_key}'
YAML
  )

  cluster_infrastructure_manifest = <<-YAML
    apiVersion: config.openshift.io/v1
    kind: Infrastructure
    metadata:
      name: cluster
    spec:
      cloudConfig:
        name: ""
    status:
      apiServerInternalURI: https://api-int.${var.cluster_domain}:6443
      apiServerURL: https://api.${var.cluster_domain}:6443
      etcdDiscoveryDomain: ${var.cluster_domain}
      infrastructureName: ${var.infrastructure_name}
      platform: AWS
      platformStatus:
        aws:
          region: ${var.region}
        type: AWS
    YAML

  cluster_dns_manifest = <<-YAML
    apiVersion: config.openshift.io/v1
    kind: DNS
    metadata:
      name: cluster
    spec:
      baseDomain: ${var.cluster_domain}
      privateZone:
        id: ${var.private_hosted_zone_id}
    status: {}
    YAML
}

resource "local_file" "install_config" {
  content  = local.install_config
  filename = "${local.install_dir}/install-config.yaml"
}

resource "null_resource" "download_openshift_install" {
  triggers = {
    url = var.openshift_installer_url
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      mkdir -p "${local.install_dir}/bin"
      cd "${local.install_dir}/bin"
      curl -fsSL "${var.openshift_installer_url}/openshift-install-linux-$(curl -fsSL ${var.openshift_installer_url}/release.txt | tr -d '\n').tar.gz" -o openshift-install.tgz
      tar xzf openshift-install.tgz openshift-install
      rm -f openshift-install.tgz
    EOT
  }
}

resource "null_resource" "create_manifests" {
  triggers = {
    install_config = sha256(local.install_config)
  }

  depends_on = [
    local_file.install_config,
    null_resource.download_openshift_install,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      rm -rf "${local.install_dir}/manifests" "${local.install_dir}/openshift"
      "${local.install_dir}/bin/openshift-install" create manifests --dir="${local.install_dir}"
      rm -f "${local.install_dir}"/openshift/99_openshift-cluster-api_master-machines-*.yaml
      rm -f "${local.install_dir}"/openshift/99_openshift-cluster-api_worker-machines*.yaml
    EOT
  }
}

resource "local_file" "cluster_infrastructure" {
  content  = local.cluster_infrastructure_manifest
  filename = "${local.install_dir}/manifests/cluster-infrastructure-02-config.yml"

  depends_on = [null_resource.create_manifests]
}

resource "local_file" "cluster_dns" {
  content  = local.cluster_dns_manifest
  filename = "${local.install_dir}/manifests/cluster-dns-02-config.yml"

  depends_on = [null_resource.create_manifests]
}

resource "local_file" "worker_machineset" {
  count = var.use_worker_machinesets ? length(var.availability_zones) : 0

  filename = "${local.install_dir}/openshift/99_openshift-cluster-api_worker-machineset-${count.index}.yaml"
  content  = templatefile("${path.module}/templates/worker-machineset.yaml.tftpl", {
    infrastructure_name   = var.infrastructure_name
    availability_zone     = var.availability_zones[count.index]
    region                = var.region
    rhcos_ami             = var.rhcos_ami
    worker_instance_type  = var.worker.instance_type
    worker_disk_gb        = var.worker.disk_gb
    worker_replicas       = floor(var.worker.count / length(var.availability_zones))
    worker_sg_id          = var.worker_security_group_id
    worker_subnet_id      = var.private_subnet_ids[count.index]
    worker_instance_profile = var.worker_instance_profile
  })

  depends_on = [null_resource.create_manifests]
}

resource "null_resource" "generate_ignition_configs" {
  triggers = {
    install_config = sha256(local.install_config)
    manifests      = sha256(join(",", concat(
      [local_file.cluster_infrastructure.content],
      [local_file.cluster_dns.content],
      local_file.worker_machineset[*].content,
    )))
  }

  depends_on = [
    local_file.cluster_infrastructure,
    local_file.cluster_dns,
    local_file.worker_machineset,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      "${local.install_dir}/bin/openshift-install" create ignition-configs --dir="${local.install_dir}"
    EOT
  }
}

resource "null_resource" "wait_bootstrap_complete" {
  depends_on = [
    aws_instance.bootstrap,
    aws_instance.master,
    aws_lb_target_group_attachment.bootstrap_internal_api,
    aws_lb_target_group_attachment.master_internal_api,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      export KUBECONFIG="${local.install_dir}/auth/kubeconfig"
      "${local.install_dir}/bin/openshift-install" wait-for bootstrap-complete --dir="${local.install_dir}" --log-level=info
    EOT
  }
}

resource "null_resource" "wait_install_complete" {
  depends_on = [null_resource.wait_bootstrap_complete]

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      "${local.install_dir}/bin/openshift-install" wait-for install-complete --dir="${local.install_dir}" --log-level=info
    EOT
  }
}
