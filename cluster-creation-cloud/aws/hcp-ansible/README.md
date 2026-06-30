# ROSA HCP Ansible Infrastructure

Complete Ansible automation for Red Hat OpenShift Service on AWS (ROSA) Hosted Control Plane clusters.

## Repository Structure

```
rosa-hcp-ansible/
├── README.md
├── ansible.cfg
├── requirements.txt
├── requirements.yml
├── inventory/
│   ├── group_vars/
│   │   └── all.yml
│   └── hosts
├── playbooks/
│   ├── create_rosa_hcp_cluster.yml
│   ├── delete_rosa_hcp_cluster.yml
│   └── validate_prerequisites.yml
├── roles/
│   ├── rosa_prerequisites/
│   ├── rosa_hcp_public/
│   ├── rosa_hcp_private/
│   └── rosa_cleanup/
└── vars/
```

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **Red Hat Account** with ROSA entitlements
3. **Tools installed locally:**
   - AWS CLI v2
   - ROSA CLI
   - Ansible 2.9+
   - Python 3.8+

## Installation

### 1. Create and Activate Virtual Environment

It's recommended to use a Python virtual environment to isolate dependencies:

```bash
# Clone the repository
git clone https://github.com/yourusername/rosa-hcp-ansible.git
cd rosa-hcp-ansible

# Create a virtual environment
python3 -m venv venv

# Activate the virtual environment
# On macOS/Linux:
source venv/bin/activate

# On Windows:
# venv\Scripts\activate
```

**Note:** After activation, your terminal prompt will show `(venv)` to indicate you're working within the virtual environment.

### 2. Install Python Dependencies

```bash
# Upgrade pip (recommended)
pip install --upgrade pip

# Install Python dependencies
pip install -r requirements.txt

# Install Ansible collections
ansible-galaxy collection install -r requirements.yml
```

### 3. Deactivate Virtual Environment (when done)

When you're finished working with the project, you can deactivate the virtual environment:

```bash
deactivate
```

**Note:** Remember to activate the virtual environment (`source venv/bin/activate`) each time you work with this project in a new terminal session.

## Configuration

### 1. Set up AWS Credentials

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

### 2. Set up ROSA Token

```bash
export ROSA_TOKEN="your-rosa-token"
```

### 3. Configure Variables

Edit `inventory/group_vars/all.yml` with your settings.

## Usage

### Validate Prerequisites

```bash
ansible-playbook playbooks/validate_prerequisites.yml
```

### Create Public ROSA HCP Cluster

```bash
ansible-playbook playbooks/create_rosa_hcp_cluster.yml \
  -e cluster_type=public \
  -e cluster_name=my-rosa-public
```

### Create Private ROSA HCP Cluster

```bash
ansible-playbook playbooks/create_rosa_hcp_cluster.yml \
  -e cluster_type=private \
  -e cluster_name=my-rosa-private
```

### Delete ROSA HCP Cluster

```bash
ansible-playbook playbooks/delete_rosa_hcp_cluster.yml \
  -e cluster_name=my-rosa-public
```

### Stop Virtual Environment

After running your playbooks, you can deactivate the virtual environment:

```bash
deactivate
```

**Note:** The virtual environment will remain active in your current terminal session until you deactivate it or close the terminal. You'll need to activate it again (`source venv/bin/activate`) for future playbook runs.

## License

MIT License


