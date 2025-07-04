# CI/CD Pipeline with Google Cloud Artifact Registry

This repository contains a complete CI/CD pipeline setup that demonstrates how to install packages from and publish to Google Cloud Artifact Registry using both Service Account and Workload Identity Federation authentication methods.

## 🚀 Quick Start

### Option 1: Automated Setup (Recommended)
Run the automated setup script to configure your Google Cloud environment:

```bash
./scripts/setup-gcp.sh
```

This script will:
- ✅ Enable required Google Cloud APIs
- ✅ Create Artifact Registry repositories (Python and Docker)
- ✅ Set up Service Account with proper permissions
- ✅ Configure Workload Identity Federation
- ✅ Generate GitHub secrets for you to copy

### Option 2: Manual Setup
Follow the detailed instructions in [`CICD_SETUP.md`](./CICD_SETUP.md) for step-by-step manual configuration.

## 📁 Repository Structure

```
├── .github/workflows/
│   ├── gcp-artifact-registry.yaml    # Main CI/CD pipeline
│   ├── deploy.yaml                   # Existing deployment workflow
│   └── test.yaml                     # Existing test workflow
├── scripts/
│   └── setup-gcp.sh                  # Automated GCP setup script
├── Dockerfile                        # Docker configuration for containerization
├── requirements.txt                  # Python dependencies with GAR examples
├── CICD_SETUP.md                    # Detailed setup instructions
└── CI_CD_README.md                  # This file
```

## 🔧 Pipeline Features

### 🧪 Test and Build Job (`test-and-build`)
- **Authentication**: Uses Workload Identity Federation (secure, keyless)
- **Package Installation**: Configures pip to install from Google Cloud Artifact Registry
- **Testing**: Runs nbdev tests
- **Building**: Creates Python wheel and source distribution
- **Verification**: Tests package installation

### 📦 Publish Job (`publish-to-artifact-registry`)
- **Trigger**: Runs only on pushes to main branch
- **Authentication**: Workload Identity Federation
- **Publishing**: Uploads Python packages to Google Cloud Artifact Registry
- **Tools**: Uses twine with OAuth2 authentication

### 🐳 Docker Job (`docker-build-push`)
- **Container Build**: Creates Docker images for the application
- **Registry Push**: Uploads to Google Cloud Artifact Registry
- **Tagging**: Tags with both commit SHA and 'latest'

## 🔐 Authentication Methods

### Workload Identity Federation (Recommended)
- ✅ **Secure**: No long-lived credentials stored in GitHub
- ✅ **Auditable**: Full audit trail in Google Cloud
- ✅ **Scalable**: Easy to manage across multiple repositories
- ✅ **Standards-based**: Uses OpenID Connect (OIDC)

### Service Account Key (Alternative)
- ⚠️ **Less secure**: Requires storing credentials as secrets
- ✅ **Simple**: Easier initial setup
- ⚠️ **Management overhead**: Keys need regular rotation

## 🛠️ Configuration

### Required GitHub Secrets
Add these to your repository: `Settings → Secrets and variables → Actions`

```bash
GCP_PROJECT_ID=your-project-id
GCP_PROJECT_NUMBER=your-project-number
GCP_REGION=us-central1
GAR_REPOSITORY=python-repo
WIF_PROVIDER=projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider
WIF_SERVICE_ACCOUNT=github-actions-sa@your-project-id.iam.gserviceaccount.com
```

### Installing Private Packages
Edit the workflow to install your private packages:

```yaml
- name: Install dependencies from Artifact Registry
  run: |
    # Replace with your actual package names
    pip install your-private-package==1.0.0
    pip install your-company-utils>=2.1.0
```

## 📋 Prerequisites

- Google Cloud Project with billing enabled
- GitHub repository with admin access
- `gcloud` CLI installed (for setup)

## 🚦 Usage

### For Pull Requests
- Pipeline runs tests and builds packages
- Verifies that private dependencies can be installed
- No publishing occurs

### For Main Branch Pushes
- Runs full test suite
- Builds and publishes Python packages to Artifact Registry
- Builds and pushes Docker images to Artifact Registry

## 🔍 Local Development

### Configure pip for Artifact Registry:
```bash
# Authenticate
gcloud auth login
gcloud auth application-default login

# Configure pip
pip config set global.index-url https://oauth2accesstoken:$(gcloud auth print-access-token)@us-central1-python.pkg.dev/YOUR_PROJECT_ID/python-repo/simple/
pip config set global.extra-index-url https://pypi.org/simple/

# Install packages
pip install your-private-package
```

### Test Docker build locally:
```bash
docker build -t hello-cicd .
docker run --rm hello-cicd
```

## 🐛 Troubleshooting

### Common Issues
1. **Authentication failures**: Check project number and WIF provider path
2. **Package not found**: Verify package exists in Artifact Registry
3. **Permission denied**: Ensure service account has correct IAM roles

### Debug Commands
```bash
# Test authentication
gcloud auth print-access-token

# List repositories
gcloud artifacts repositories list

# List packages
gcloud artifacts packages list --repository=python-repo --location=us-central1

# Check pip configuration
pip config list
```

## 📚 Documentation

- **[CICD_SETUP.md](./CICD_SETUP.md)**: Complete setup instructions
- **[requirements.txt](./requirements.txt)**: Example dependencies configuration
- **[Dockerfile](./Dockerfile)**: Container configuration
- **[scripts/setup-gcp.sh](./scripts/setup-gcp.sh)**: Automated setup script

## 🔗 External Resources

- [Google Cloud Artifact Registry Documentation](https://cloud.google.com/artifact-registry/docs)
- [Workload Identity Federation Guide](https://cloud.google.com/iam/docs/workload-identity-federation)
- [GitHub Actions Security Best Practices](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test your changes with the CI/CD pipeline
4. Submit a pull request

## 📄 License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.