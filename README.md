# HA NGINX on AWS

This project sets up a simple but production-ready web setup on AWS where if one server goes down, the website keeps running and AWS automatically brings a new server back up — no manual work needed.

I used CloudFormation because thats what I've been working with for the last 6 years at IBM/Kyndryl. I've used it across real client environments like Allstate and Honda so it made sense to go with what I know well rather than learn something new for this task. AWS Sydney region keeps the cost under AUD 20/month too.

---


There are always 2 servers running behind a load balancer. The load balancer splits traffic between them and checks every 30 seconds that each server is responding. If a server stops responding, AWS kills it and starts a fresh one automatically using the same template. The website never goes down.

```
         Internet
             |
    [ Load Balancer ]
       /           \
  [ Server 1 ]  [ Server 2 ]
    Sydney AZ-a   Sydney AZ-b
       \           /
    [ Auto Scaling Group ]
       watches both servers
       replaces any that die
```

---

## Project Structure

```
templates/
  01-networking.yaml    # VPC, subnets, firewall rules
  02-loadbalancer.yaml  # Load balancer setup
  03-compute.yaml       # servers and auto scaling
Dockerfile              # packages NGINX into a container
deploy.sh               # one command to deploy everything
```

**Why three separate files?**
Keeps things clean. Networking doesn't change often. Load balancer sits in the middle. Compute is what you touch most — scaling, instance type, AMI updates. Splitting them means you can update one without touching the others.

---

## How to Run It

**See what will be created (no changes made):**

```bash
aws cloudformation create-change-set \
  --stack-name ha-nginx-dev-networking \
  --template-body file://templates/01-networking.yaml \
  --change-set-name preview \
  --change-set-type CREATE \
  --parameters ParameterKey=ProjectName,ParameterValue=ha-nginx \
               ParameterKey=Environment,ParameterValue=dev \
  --region ap-southeast-2

aws cloudformation describe-change-set \
  --stack-name ha-nginx-dev-networking \
  --change-set-name preview \
  --output table \
  --region ap-southeast-2
```

Do the same for 02-loadbalancer.yaml and 03-compute.yaml.

**Actually deploy everything:**

```bash
chmod +x deploy.sh
./deploy.sh
```

Thats it. One command, all three stacks deploy in the right order. At the end it prints the URL you open in a browser.

Run it a second time — nothing changes. CloudFormation compares what's already running with the template and does nothing if they match.

---

## The Docker Part 

Instead of installing NGINX directly on the server, I packaged it into a Docker container. Each new server that starts up automatically pulls the image and runs it. That means every server is identical — no configuration drift.

The image lives at `ghcr.io/shamindergarg/ha-nginx:latest` (GitHub Container Registry, its free).

To test locally:

```bash
docker build -t ha-nginx .
docker run -p 8080:80 ha-nginx
# open http://localhost:8080
```

---

## What Happens When a Server Dies

1. server stops responding
2. Load balancer health check fails twice in a row
3. Auto Scaling Group marks it as unhealthy
4. AWS terminates it and starts a new one from the same template
5. New server boots, pulls Docker image, starts NGINX
6. Health check passes, traffic flows to it again

All of this happens in about 2-3 minutes with zero manual steps.

---

## Cost Estimate (Sydney Region)

| What | Per Month |
|------|-----------|
| 2 x t3.micro servers | ~AUD 14.80 |
| Load balancer | ~AUD 2.50 |
| Data transfer | ~AUD 0.50 |
| Total | ~AUD 17.80 |

Well under the AUD 20 limit. If this were a real prod workload I'd look at Reserved Instances which cuts the EC2 cost by around 40%.

---

## A Few Decisions I Made

**Public subnets instead of private** — in a real production setup servers would sit in private subnets behind a NAT Gateway. I skipped that here because NAT Gateway costs around AUD 35/month on its own which blows the budget. Easy to add later.

**No SSH key pair** — I attached an IAM role with SSM access instead. You can shell into any instance through the AWS console without opening port 22. Cleaner and more secure.

**AMI resolved automatically** — rather than hardcoding an AMI ID which goes stale, I'm pulling the latest Amazon Linux 2023 AMI from SSM Parameter Store at deploy time.

**HTTPS not included** — port 80 only as per scope. Adding HTTPS would just mean an ACM cert and a second listener on the ALB, maybe 10 mins of work.

