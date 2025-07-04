#!/bin/bash

# Setup script for Google Cloud Artifact Registry CI/CD
# This script automates the setup of Google Cloud resources for the GitHub Actions CI/CD pipeline

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are installed
check_requirements() {
    print_status "Checking requirements..."
    
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_warning "jq is not installed. Some features may not work properly."
    fi
}

# Get user input
get_user_input() {
    echo -e "\n${GREEN}Setting up Google Cloud for CI/CD pipeline${NC}"
    echo "Please provide the following information:"
    
    read -p "Enter your Google Cloud Project ID: " PROJECT_ID
    read -p "Enter your GitHub username: " GITHUB_USERNAME
    read -p "Enter your GitHub repository name: " GITHUB_REPO
    read -p "Enter the region for Artifact Registry (default: us-central1): " REGION
    REGION=${REGION:-us-central1}
    
    read -p "Enter Python repository name (default: python-repo): " PYTHON_REPO
    PYTHON_REPO=${PYTHON_REPO:-python-repo}
    
    read -p "Enter Docker repository name (default: docker-repo): " DOCKER_REPO
    DOCKER_REPO=${DOCKER_REPO:-docker-repo}
    
    echo -e "\n${YELLOW}Configuration Summary:${NC}"
    echo "Project ID: $PROJECT_ID"
    echo "GitHub: $GITHUB_USERNAME/$GITHUB_REPO"
    echo "Region: $REGION"
    echo "Python Repository: $PYTHON_REPO"
    echo "Docker Repository: $DOCKER_REPO"
    
    read -p "Continue with this configuration? (y/N): " confirm
    if [[ $confirm != [yY] ]]; then
        print_error "Setup cancelled."
        exit 1
    fi
}

# Set up Google Cloud project
setup_project() {
    print_status "Setting up Google Cloud project..."
    
    gcloud config set project "$PROJECT_ID"
    
    # Get project number
    PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
    print_status "Project number: $PROJECT_NUMBER"
}

# Enable required APIs
enable_apis() {
    print_status "Enabling required APIs..."
    
    gcloud services enable artifactregistry.googleapis.com \
        iamcredentials.googleapis.com \
        sts.googleapis.com \
        cloudresourcemanager.googleapis.com
}

# Create Artifact Registry repositories
create_repositories() {
    print_status "Creating Artifact Registry repositories..."
    
    # Python repository
    if gcloud artifacts repositories describe "$PYTHON_REPO" --location="$REGION" &>/dev/null; then
        print_warning "Python repository '$PYTHON_REPO' already exists"
    else
        gcloud artifacts repositories create "$PYTHON_REPO" \
            --repository-format=python \
            --location="$REGION" \
            --description="Python packages repository for CI/CD"
        print_status "Created Python repository: $PYTHON_REPO"
    fi
    
    # Docker repository
    if gcloud artifacts repositories describe "$DOCKER_REPO" --location="$REGION" &>/dev/null; then
        print_warning "Docker repository '$DOCKER_REPO' already exists"
    else
        gcloud artifacts repositories create "$DOCKER_REPO" \
            --repository-format=docker \
            --location="$REGION" \
            --description="Docker images repository for CI/CD"
        print_status "Created Docker repository: $DOCKER_REPO"
    fi
}

# Create service account
create_service_account() {
    print_status "Creating service account..."
    
    SA_NAME="github-actions-sa"
    SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "$SA_EMAIL" &>/dev/null; then
        print_warning "Service account '$SA_EMAIL' already exists"
    else
        gcloud iam service-accounts create "$SA_NAME" \
            --display-name="GitHub Actions Service Account" \
            --description="Service account for GitHub Actions CI/CD"
        print_status "Created service account: $SA_EMAIL"
    fi
    
    # Grant permissions
    print_status "Granting permissions to service account..."
    
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/artifactregistry.reader"
    
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/artifactregistry.writer"
    
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/storage.admin"
}

# Set up Workload Identity Federation
setup_workload_identity() {
    print_status "Setting up Workload Identity Federation..."
    
    POOL_ID="github-pool"
    PROVIDER_ID="github-provider"
    
    # Create workload identity pool
    if gcloud iam workload-identity-pools describe "$POOL_ID" --location="global" &>/dev/null; then
        print_warning "Workload identity pool '$POOL_ID' already exists"
    else
        gcloud iam workload-identity-pools create "$POOL_ID" \
            --location="global" \
            --display-name="GitHub Actions Pool" \
            --description="Identity pool for GitHub Actions"
        print_status "Created workload identity pool: $POOL_ID"
    fi
    
    # Create OIDC provider
    if gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
        --location="global" --workload-identity-pool="$POOL_ID" &>/dev/null; then
        print_warning "Workload identity provider '$PROVIDER_ID' already exists"
    else
        gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
            --location="global" \
            --workload-identity-pool="$POOL_ID" \
            --display-name="GitHub Actions Provider" \
            --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
            --issuer-uri="https://token.actions.githubusercontent.com"
        print_status "Created workload identity provider: $PROVIDER_ID"
    fi
    
    # Bind service account to workload identity
    SA_EMAIL="github-actions-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    POOL_FULL_ID="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}"
    
    gcloud iam service-accounts add-iam-policy-binding \
        "$SA_EMAIL" \
        --role="roles/iam.workloadIdentityUser" \
        --member="principalSet://iam.googleapis.com/${POOL_FULL_ID}/attribute.repository/${GITHUB_USERNAME}/${GITHUB_REPO}"
    
    print_status "Bound service account to workload identity"
}

# Generate GitHub secrets
generate_github_secrets() {
    print_status "Generating GitHub secrets configuration..."
    
    WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
    SA_EMAIL="github-actions-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    cat > github-secrets.txt << EOF
# Add these secrets to your GitHub repository
# Go to: Settings → Secrets and variables → Actions

GCP_PROJECT_ID=${PROJECT_ID}
GCP_PROJECT_NUMBER=${PROJECT_NUMBER}
GCP_REGION=${REGION}
GAR_REPOSITORY=${PYTHON_REPO}
WIF_PROVIDER=${WIF_PROVIDER}
WIF_SERVICE_ACCOUNT=${SA_EMAIL}
EOF
    
    print_status "GitHub secrets saved to: github-secrets.txt"
    
    echo -e "\n${GREEN}Setup complete!${NC}"
    echo -e "\n${YELLOW}Next steps:${NC}"
    echo "1. Add the secrets from 'github-secrets.txt' to your GitHub repository"
    echo "2. Commit and push the CI/CD workflow files"
    echo "3. Test the pipeline by creating a pull request or pushing to main"
    echo ""
    echo "For detailed instructions, see: CICD_SETUP.md"
}

# Main execution
main() {
    check_requirements
    get_user_input
    setup_project
    enable_apis
    create_repositories
    create_service_account
    setup_workload_identity
    generate_github_secrets
}

# Run main function
main "$@"