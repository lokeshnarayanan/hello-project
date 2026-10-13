Description: Python (Flask)+ git and github (github webhook) + docker and dockerHub + jenkins + Ngrok + Terraform + Eks + GKS + Prometheus + grafana + Helm + ArgoCD
Create app.py
from flask import Flask
app = Flask(name)
@app.route("/")
def hello():
return "Hello vishal this is final hello project!"  
@app.route("/new")
def new():
return "FINAL CHECK"  
if name == "main":
app.run(host="0.0.0.0", port=5005)

Create requirements.txt
Flask
>> Run: pip install -r requirements.txt

Create Dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt   .
COPY app.py   .
RUN pip install --no-cache-dir -r requirements.txt
EXPOSE 5005
CMD ["python", "app.py"]
>> Run: docker login
>> Run: docker build -t <docker-username/hello:v1> .
>> Run: docker push <docker-username/hello:v1>
Create Jenkinsfile
---
pipeline {
agent any
    environment {
        image_name = "devoopsguru/hello"
    }
    stages {
        stage("git-checkout") {
            steps {
                checkout scm
            }
        }
        stage("image-build") {
            steps {
                script {
                    env.image_tag = new Date().format("yyyy-MM-dd-HHmmss")
                    env.full_image = "${env.image_name}:${env.image_tag}"
                }
            }
        }
        stage("docker login") {
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: 'docker_cred', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                        sh "docker login -u ${DOCKER_USERNAME} -p ${DOCKER_PASSWORD}"
                    }
                }
            }
        }
        stage("docker push") {
            steps {
                script {
                    sh "docker build -t ${env.full_image} ."
                    sh "docker push ${env.full_image}"
                }
            }
        }
    }
}

Create Cluster via terraform
###############################################################################
TERRAFORM + AWS PROVIDER
###############################################################################
terraform {
required_version = ">= 1.5.7"
required_providers {
aws = {
source  = "hashicorp/aws"
version = ">= 6.59"
}
}
}
provider "aws" {
region = var.aws_region
}

###############################################################################
VARIABLES
###############################################################################
variable "aws_region" {
description = "AWS region"
type        = string
default     = "ap-south-2"
}
variable "cluster_name" {
description = "EKS cluster name"
type        = string
default     = "terraform-eks"
}
variable "cluster_version" {
description = "Kubernetes version"
type        = string
default     = "1.33"
}

###############################################################################
VPC
###############################################################################
module "vpc" {
source  = "terraform-aws-modules/vpc/aws"
version = "~> 6.0"
name = "${var.cluster_name}-vpc"
cidr = "10.0.0.0/16"
EKS requires subnets in at least 2 AZs
azs = [
"${var.aws_region}a",
"${var.aws_region}b"
]
Private subnets for EKS worker nodes
private_subnets = [
"10.0.1.0/24",
"10.0.2.0/24"
]
Public subnets
public_subnets = [
"10.0.101.0/24",
"10.0.102.0/24"
]
Internet access for private subnets
enable_nat_gateway = true
One NAT Gateway to reduce cost
single_nat_gateway = true
enable_dns_hostnames = true
enable_dns_support   = true
tags = {
Terraform   = "true"
Environment = "dev"
}
}

###############################################################################
EKS CLUSTER
###############################################################################
module "eks" {
source  = "terraform-aws-modules/eks/aws"
version = "~> 21.0"
name = var.cluster_name
kubernetes_version = var.cluster_version
Allow kubectl access from local machine
endpoint_public_access = true
Give cluster creator admin access
enable_cluster_creator_admin_permissions = true

###########################################################################
EKS ADDONS
###########################################################################
addons = {
    coredns = {}

    eks-pod-identity-agent = {
      before_compute = true
    }

    kube-proxy = {}

    vpc-cni = {
      before_compute = true
    }
}

###########################################################################
NETWORKING
###########################################################################
vpc_id = module.vpc.vpc_id
Worker nodes in private subnets
subnet_ids = module.vpc.private_subnets

###########################################################################
MANAGED NODE GROUP
###########################################################################
eks_managed_node_groups = {
    general = {

      name = "general-node-group"


      #######################################################################
      # INSTANCE TYPE
      #######################################################################

      # Small instance for learning/testing
      instance_types = ["t3.micro"]


      #######################################################################
      # AMI
      #######################################################################

      # IMPORTANT:
      # ami_type is NOT an AMI ID.
      # Use a supported EKS AMI type.
      ami_type = "AL2023_x86_64_STANDARD"


      #######################################################################
      # NODE SCALING
      #######################################################################

      # Start with 2 nodes so CoreDNS and other system pods
      # have enough pod capacity.
      min_size     = 7
      desired_size = 7
      max_size     = 9


      #######################################################################
      # STORAGE
      #######################################################################

      disk_size = 28


      #######################################################################
      # CAPACITY TYPE
      #######################################################################

      capacity_type = "ON_DEMAND"


      #######################################################################
      # NODE LABELS
      #######################################################################

      labels = {
        Environment = "dev"
        NodeGroup   = "general"
      }


      #######################################################################
      # NODE TAGS
      #######################################################################

      tags = {
        Name        = "${var.cluster_name}-worker"
        Environment = "dev"
        Terraform   = "true"
      }

    }

}

###########################################################################
EKS TAGS
###########################################################################
tags = {
Environment = "dev"
Terraform   = "true"
}
}

###############################################################################
OUTPUTS
###############################################################################
output "cluster_name" {
description = "EKS cluster name"
value = module.eks.cluster_name
}

output "cluster_endpoint" {
description = "EKS API endpoint"
value = module.eks.cluster_endpoint
}

output "cluster_version" {
description = "Kubernetes version"
value = module.eks.cluster_version
}

output "vpc_id" {
description = "VPC ID"
value = module.vpc.vpc_id
}

output "private_subnets" {
description = "Private subnet IDs"
value = module.vpc.private_subnets
}

output "node_group" {
description = "EKS managed node group"
value = module.eks.eks_managed_node_groups
}
>> Run: terraform init
>> Run: terraform validate
>> Run: terraform plan
>> Run: terraform apply
>> Run: aws eks update-kubeconfig --region ap-south-2 --name terraform-eks
>> Run: kubectl get nodes
Create Deployment and service file : deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
name: hello-world-deployment
labels:
app: hello-world
spec:
replicas: 2
selector:
matchLabels:
app: hello-world
template:
metadata:
labels:
app: hello-world
spec:
containers:
- name: hello-world
image: devoopsguru/hello:v4
ports:
- containerPort: 5005
---
apiVersion: v1
kind: Service
metadata:
name: hello-world-service
labels:
app: hello-world
spec:
type: LoadBalancer
selector:
app: hello-world
ports:
name: web
protocol: TCP
port: 80
targetPort: 5005
> Run: kubectl apply -f deployment.yaml
Monitoring tools ( prometheus and grafana)
> helm version
> helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
> helm repo update
> helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace --timeout 10m
> kubectl get ns
> kubectl get all ns 
> kubectl get all -n monitoring
> kubectl get ns && kubectl get all -n monitoring
> kubectl -n monitoring get pvc
> kubectl -n monitoring get prometheus,alertmanager,servicemonitor

Now modify the requirement.txt file
add the content :
prometheus-client==0.21.0
prometheus-flask-exporter==0.23.1
Now modify the app.py file
from prometheus_flask_exporter import PrometheusMetrics
metrics = PrometheusMetrics(app) # enble/metrics
or whole file like :
---
from flask import Flask
from prometheus_flask_exporter import PrometheusMetrics
app = Flask(name)
metrics = PrometheusMetrics(app)   # <-- enables /metrics
@app.route("/")
def hello():
return "Hello World!"
@app.route("/new")
def new():
return "FINAL CHECK"
if name == "main":
app.run(host="0.0.0.0", port=5005)

---
On Kubernetes (via the LoadBalancer):
bash
kubectl get svc hello-world-service
then
curl http://<EXTERNAL-IP>/metrics
http://[IP_ADDRESS]/metrics --> prometheus

---
create the servicemonitor.yaml file
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
name: hello-service
namespace: monitoring
labels:
release: prometheus
spec:
selector:
matchLabels:
app: hello
namespaceSelector:
matchNames:
- default
endpoints:
port: web
path: /metrics
interval: 15s
---
> kubectl apply -f servicemonitor.yaml &&  kubectl get all -n monitoring
> kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
Grafana Dashboard
Create a file "nano grafana-values.yaml":
grafana:
grafana.ini:
security:
csrf_trusted_origins: 3000-cs-272023480814-default.cs-asia-southeast1-seal.cloudshell.dev
or
cat > grafana-values.yaml <<'EOF'
grafana:
grafana.ini:
security:
csrf_trusted_origins: 3000-cs-272023480814-default.cs-asia-southeast1-seal.cloudshell.dev
EOF
helm upgrade prometheus prometheus-community/kube-prometheus-stack   
-n monitoring --reuse-values -f grafana-values.yaml
kubectl rollout status deployment/prometheus-grafana -n monitoring
> Run: helm upgrade prometheus prometheus-community/kube-prometheus-stack   -n monitoring --reuse-values -f grafana-values.yaml
> Run: > kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
> Run: kubectl rollout restart deployment/prometheus-grafana -n monitoring
> grafana password:
kubectl --namespace monitoring get secrets prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo
or
kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d; echo

---

Continous delivery ( ArgoCD )
Automate the CI
---
add the stage in the jenkinsfile
stage('Update Deployment File') {
steps {
sh """
sed -i 's|image: .*|image: ${DOCKERHUB_USERNAME}/flask-hello:${IMAGE_TAG}|' deployment.yaml
        git config user.name "Jenkins"
        git config user.email "jenkins@example.com"

        git add deployment.yaml
        git commit -m "Deploy new image ${IMAGE_TAG}"
        git push
        """
    }
}
whole pipeline
pipeline {
agent any
    environment {
        IMAGE_NAME = "devoopsguru/hello"
        DEPLOYMENT_FILE = "deployment.yaml"
    }

    stages {

        stage('Git Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Generate Image Tag') {
            steps {
                script {
                    env.IMAGE_TAG = new Date().format("yyyy-MM-dd-HHmmss")
                    env.FULL_IMAGE = "${IMAGE_NAME}:${IMAGE_TAG}"

                    echo "Image Name: ${FULL_IMAGE}"
                }
            }
        }

        stage('Docker Login') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'docker_cred',
                        usernameVariable: 'DOCKER_USERNAME',
                        passwordVariable: 'DOCKER_PASSWORD'
                    )
                ]) {

                    sh '''
                    echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
                    '''
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                docker build -t ${FULL_IMAGE} .
                '''
            }
        }

        stage('Push Docker Image') {
            steps {
                sh '''
                docker push ${FULL_IMAGE}
                '''
            }
        }

        stage('Update Kubernetes Deployment File') {
            steps {
                sh """
                sed -i 's|image: .*|image: ${FULL_IMAGE}|' ${DEPLOYMENT_FILE}

                git config user.name "Jenkins"
                git config user.email "jenkins@example.com"

                git add ${DEPLOYMENT_FILE}
                git commit -m "Updated image to ${FULL_IMAGE}" || echo "No changes to commit"

                git push
                """
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                sh '''
                kubectl apply -f deployment.yaml
                '''
            }
        }

    }

    post {

        success {
            echo "Pipeline executed successfully"
        }

        failure {
            echo "Pipeline failed"
        }

    }
}
Install the ArgoCD
kubectl create namespace argocd && kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
> kubeclt get all -n argocd
> kubectl get pods -n argocd -w
Access the UI from Cloud Shell:
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"LoadBalancer"}}'
kubectl get svc argocd-server -n argocd -w

Username and passward
Username: admin
Password:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
after the login
click on application and set-up that.
General:
Appication Name: demo or any
Project Name: Default
Sync Policy: Automati and check-mark down box.
Source:
Repo link:
Revision: main
Path: .
Destination:
Cluster URL : default on chooose
NameSpace: default
Scroll up and click on edit as yaml

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
name: hello-world
namespace: argocd
spec:
project: default
source:
repoURL: https://github.com/<username>/hello.git
targetRevision: main
path: .
destination:
server: https://kubernetes.default.svc
namespace: default
syncPolicy:
automated:
prune: true
selfHeal: true
Save and exit
> kubectl apply -f hello-app.yaml
> kubectl get applications -n argocd

Now check the replicas and enjoy the full projet automate.