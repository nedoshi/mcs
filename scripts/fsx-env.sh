export CLUSTER=$(terraform output -raw cluster_name)
export FSX_REGION=$(terraform output -raw region)
export FSX_NAME="${CLUSTER}-FSXONTAP"
export FSX_SUBNET1="$(terraform output -json private_subnet_ids | jq -r '.[0]')"
export FSX_SUBNET2="$(terraform output -json private_subnet_ids | jq -r '.[1]')"
export FSX_VPC="$(terraform output -raw vpc_id)"
export FSX_VPC_CIDR="$(terraform output -raw vpc_cidr)"
export METAL_AZ="$(terraform output -json availability_zones | jq -r '.[0]')"
export FSX_ROUTE_TABLES="$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=${FSX_VPC}" "Name=tag:Name,Values=${CLUSTER}-rtb-private*" \
  --query 'RouteTables[].RouteTableId' --output text | tr '\t' ',')"
export FSX_ADMIN_PASS="$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 16; echo)"
export SVM_ADMIN_PASS="$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 16; echo)"
