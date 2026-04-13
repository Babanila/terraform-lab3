# How to create this infrastructure is laid down below

# Refactor with Variables & Deploy a Web Server

**Duration:** ~60 min
**Goal:** Take the VPC from Lab 2, refactor it to use variables, then add a security group and an EC2 instance running nginx. **Finish with a clean destroy.**

## Step 1 — Start from Lab 2

```bash
cp -r ~/terraform-lab2 ~/terraform-lab3
cd ~/terraform-lab3
rm -rf .terraform .terraform.lock.hcl terraform.tfstate*
```

We wipe the `.terraform` and state because Lab 3 is a fresh project — we're copying the code, not the deployment.

## Step 2 — Split the files

```bash
touch variables.tf outputs.tf terraform.tfvars
```

Move the `terraform { ... }` block and the `provider "aws" { ... }` block into the top of `main.tf` (they should already be there). Now create `variables.tf`:

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "student_name" {
  description = "Your name — suffix for every resource to avoid collisions"
  type        = string
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "lab"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.20.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}
```

And `terraform.tfvars`:

```hcl
student_name = "baba"
```

## Step 3 — Replace hardcoded values in `main.tf`

Update the provider and existing resources:

```hcl
provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "vpc-${var.student_name}"
    Environment = var.environment
    Lab         = "03"
    ManagedBy   = "terraform"
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "igw-${var.student_name}" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
  tags                    = { Name = "subnet-public-${var.student_name}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = { Name = "rt-public-${var.student_name}" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
```

## Step 4 — Init and plan

```bash
terraform init
terraform fmt
terraform validate
terraform plan
```

You should see `Plan: 5 to add, 0 to change, 0 to destroy.` — same infrastructure as Lab 2, just expressed with variables.

```bash
terraform apply
```

## Step 5 — Add the security group

Append to `main.tf`:

```hcl
resource "aws_security_group" "web" {
  name        = "scg-web-${var.student_name}"
  description = "Allow HTTP and SSH"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # In real work, lock this to your office IP!
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "scg-web-${var.student_name}" }
}
```

## Step 6 — Add the EC2 instance with a data source

We want the latest Ubuntu AMI without hardcoding an ID (AMI IDs change over time and differ per region). Use a **data source**:

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical

	filter {
	  name   = "name"
	  values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
	}
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public.id

  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    echo "<h1>Hello from ${var.student_name}'s Terraform-built server!</h1>" > /var/www/html/index.html
    systemctl enable --now nginx
  EOF

  tags = {
    Name        = "web-${var.student_name}"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
```

## Step 7 — Outputs

Edit `outputs.tf`:

```hcl
output "instance_public_ip" {
  description = "Public IP of the web server"
  value       = aws_instance.web.public_ip
}

output "instance_public_dns" {
  description = "Public DNS name"
  value       = aws_instance.web.public_dns
}

output "web_url" {
  description = "URL to open in your browser"
  value       = "http://${aws_instance.web.public_dns}"
}
```

## Step 8 — Apply and test

```bash
terraform plan
terraform apply
```

Copy the `web_url` from the output and open it in a browser. Give nginx about 30 seconds if you get "connection refused" — `user_data` runs after the instance reports as "running".

You should see: **"Hello from baba's Terraform-built server!"**

## Step 9 — Make a change, read the plan carefully

Change the nginx message in `user_data`:

```hcl
echo "<h1>Hello from ${var.student_name} — version 2!</h1>" > /var/www/html/index.html
```

Run:

```bash
terraform plan
```

Terraform tells you it will **replace** the instance (user_data changes force a new instance). Notice the `-/+` marker — in production, this is where you stop and think: "Do I really want to replace this?" For a stateless web server, fine. For a database, **absolutely not**. This is why reading the plan matters.

Apply if you want, or revert.

## Step 10 — Override a variable from the CLI

Try the precedence rules from the lesson:

```bash
terraform plan -var="environment=staging"
```

Notice the tags in the plan output change. This is how CI/CD pipelines deploy the same code to different environments.

## Step 11 — Destroy

```bash
terraform destroy
```

Read the plan (`Plan: 0 to add, 0 to change, 8 to destroy.`), type `yes`. In about a minute, your entire environment is gone.

## Deliverables

1. Contents of `main.tf`, `variables.tf`, `outputs.tf`, `terraform.tfvars`.
2. Screenshot of `terraform plan` before the first apply.
3. Screenshot of the nginx page showing your name.
4. Screenshot of the `/+` replace-plan from Step 9.
5. Screenshot of `terraform destroy` completing.

## Stretch goals

1. **Restrict SSH** to your own IP using a variable `my_ip_cidr`.
2. **Second AZ:** add a second subnet in `${var.aws_region}b` and a second EC2 instance there.
3. **S3 bucket** with a random suffix using the `random_id` resource from the `random` provider.
4. **Use `for_each`** to create 3 EC2 instances from a `map` variable.

## Key takeaways

- IaC replaces ClickOps with reviewable, reproducible, version-controlled infrastructure.
- Terraform is declarative: you describe desired state, it figures out the diff.
- The sacred workflow: **write → init → fmt → validate → plan → apply**. Never skip `plan`.
- Variables make the same code work for dev, staging, and prod.
- Data sources let you query existing infrastructure without managing it.
- State is the source of truth for what Terraform manages. Protect it.
- `terraform destroy` is the cheapest feature in cloud engineering. Use it daily in lab environments.
