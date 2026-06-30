output "bootstrap_instance_id" {
  value = aws_instance.bootstrap.id
}

output "master_instance_ids" {
  value = aws_instance.master[*].id
}

output "install_dir" {
  value = local.install_dir
}
