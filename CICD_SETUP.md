# CI/CD Pipeline Setup with Google Cloud Artifact Registry

This guide explains how to set up a complete CI/CD pipeline that installs packages from and publishes to Google Cloud Artifact Registry using Workload Identity Federation (WIF) authentication.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Google Cloud Setup](#google-cloud-setup)
3. [Workload Identity Federation Setup](#workload-identity-federation-setup)
4. [GitHub Repository Setup](#github-repository-setup)
5. [Pipeline Features](#pipeline-features)
6. [Troubleshooting](#troubleshooting)

## Prerequisites

- Google Cloud Project with billing enabled
- GitHub repository
- Admin access to both Google Cloud and GitHub repository
- `gcloud` CLI installed locally (for setup)

## Google Cloud Setup

### 1. Enable Required APIs

```bash
gcloud config set project YOUR_PROJECT_ID

# Enable required APIs
gcloud services enable artifactregistry.googleapis.com
gcloud services enable iamcredentials.googleapis.com
gcloud services enable sts.googleapis.com
```

### 2. Create Artifact Registry Repositories

```bash
# For Python packages
gcloud artifacts repositories create python-repo \
    --repository-format=python \
    --location=us-central1 \
    --description="Python packages repository"

# For Docker images (optional)
gcloud artifacts repositories create docker-repo \
    --repository-format=docker \
    --location=us-central1 \
    --description="Docker images repository"
```

### 3. Create Service Account

```bash
# Create service account
gcloud iam service-accounts create github-actions-sa \
    --display-name="GitHub Actions Service Account" \
    --description="Service account for GitHub Actions CI/CD"

# Get the service account email
export SA_EMAIL="github-actions-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com"
```

### 4. Grant Permissions to Service Account

```bash
# Artifact Registry permissions
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/artifactregistry.reader"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/artifactregistry.writer"

# Additional permissions if needed
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/storage.admin"
```

## Workload Identity Federation Setup

### 1. Create Workload Identity Pool

```bash
# Create the pool
gcloud iam workload-identity-pools create "github-pool" \
    --location="global" \
    --display-name="GitHub Actions Pool" \
    --description="Identity pool for GitHub Actions"

# Get the pool ID
export WORKLOAD_IDENTITY_POOL_ID="github-pool"
export POOL_FULL_ID="projects/YOUR_PROJECT_NUMBER/locations/global/workloadIdentityPools/${WORKLOAD_IDENTITY_POOL_ID}"
```

### 2. Create Workload Identity Provider

```bash
# Create the provider for GitHub Actions
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
    --location="global" \
    --workload-identity-pool="github-pool" \
    --display-name="GitHub Actions Provider" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
    --issuer-uri="https://token.actions.githubusercontent.com"

# Get the provider full name
export WIF_PROVIDER="projects/YOUR_PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
```

### 3. Bind Service Account to Workload Identity

```bash
# Allow GitHub Actions from your repository to impersonate the service account
gcloud iam service-accounts add-iam-policy-binding \
    "${SA_EMAIL}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/${POOL_FULL_ID}/attribute.repository/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME"

# For organization-wide access (optional)
# gcloud iam service-accounts add-iam-policy-binding \
#     "${SA_EMAIL}" \
#     --role="roles/iam.workloadIdentityUser" \
#     --member="principalSet://iam.googleapis.com/${POOL_FULL_ID}/attribute.repository_owner/YOUR_GITHUB_ORG"
```

## GitHub Repository Setup

### 1. Required GitHub Secrets

Add the following secrets to your GitHub repository (Settings → Secrets and variables → Actions):

```bash
# Required secrets
GCP_PROJECT_ID=your-project-id
GCP_PROJECT_NUMBER=your-project-number  # Found in GCP Console
GCP_REGION=us-central1
GAR_REPOSITORY=python-repo  # or docker-repo for Docker images
WIF_PROVIDER=projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider
WIF_SERVICE_ACCOUNT=github-actions-sa@your-project-id.iam.gserviceaccount.com
```

### 2. Find Your Project Number

```bash
# Get project number
gcloud projects describe YOUR_PROJECT_ID --format="value(projectNumber)"
```

### 3. Alternative: Service Account Key Method (Less Secure)

If you prefer to use Service Account keys instead of WIF:

```bash
# Create and download service account key
gcloud iam service-accounts keys create key.json \
    --iam-account="${SA_EMAIL}"

# Add the entire content of key.json as a GitHub secret named GCP_SA_KEY
```

## Pipeline Features

The CI/CD pipeline includes:

### Test and Build Job
- ✅ Authenticates with Google Cloud using WIF
- ✅ Configures pip to install from Artifact Registry
- ✅ Installs private packages from GAR
- ✅ Runs tests using nbdev
- ✅ Builds Python package
- ✅ Verifies package installation

### Publish Job
- ✅ Publishes Python packages to Artifact Registry
- ✅ Runs only on main branch pushes
- ✅ Uses Workload Identity Federation for secure authentication

### Docker Job (Optional)
- ✅ Builds Docker images
- ✅ Pushes to Google Cloud Artifact Registry
- ✅ Tags with commit SHA and 'latest'

## Using the Pipeline

### Installing Private Packages

To install packages from your Artifact Registry in the pipeline, edit the workflow file:

```yaml
- name: Install dependencies from Artifact Registry
  run: |
    # Replace 'your-private-package' with actual package names
    pip install your-private-package==1.0.0
    pip install another-private-package>=2.1.0
```

### Local Development Setup

To install packages locally from Artifact Registry:

```bash
# Authenticate with gcloud
gcloud auth login
gcloud auth application-default login

# Configure pip
pip config set global.index-url https://oauth2accesstoken:$(gcloud auth print-access-token)@us-central1-python.pkg.dev/YOUR_PROJECT_ID/python-repo/simple/
pip config set global.extra-index-url https://pypi.org/simple/

# Install packages
pip install your-private-package
```

## Troubleshooting

### Common Issues

1. **Authentication Errors**
   ```
   Error: Could not setup workload identity federation
   ```
   - Verify project number is correct
   - Check WIF provider path
   - Ensure service account has correct permissions

2. **Package Installation Failures**
   ```
   ERROR: Could not find a version that satisfies the requirement
   ```
   - Check if package exists in Artifact Registry
   - Verify authentication is working
   - Ensure pip is configured correctly

3. **Permission Denied**
   ```
   403 Permission denied
   ```
   - Check service account has `artifactregistry.reader` role
   - Verify Workload Identity binding
   - Check if repository exists

### Debugging Commands

```bash
# Test authentication locally
gcloud auth print-access-token

# List repositories
gcloud artifacts repositories list

# List packages in repository
gcloud artifacts packages list --repository=python-repo --location=us-central1

# Test pip configuration
pip config list
```

### Logs and Monitoring

- Check GitHub Actions logs for detailed error messages
- Use `gcloud logging` to view Cloud IAM and Artifact Registry logs
- Monitor authentication requests in Cloud Console

## Security Best Practices

1. **Use Workload Identity Federation** instead of service account keys
2. **Limit repository access** in WIF binding to specific repositories
3. **Use least privilege principle** when granting IAM roles
4. **Regularly rotate** any service account keys if used
5. **Monitor access logs** in Cloud Console
6. **Use branch protection** rules to prevent unauthorized changes

## Additional Resources

- [Workload Identity Federation Documentation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [Artifact Registry Python Documentation](https://cloud.google.com/artifact-registry/docs/python)
- [GitHub Actions Security Hardening](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)