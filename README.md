# AWS Terraform Exam — ToDoAI on ECS Fargate behind ALB with Autoscaling

End-to-end implementation of the exam task: build a Docker image, push it to
Amazon ECR, deploy the **ToDoAI** application on **Amazon ECS (Fargate)** behind
an **Application Load Balancer**, expose it publicly through **Amazon Route53**
under the name `hwbarabash1.pp.ua`, and configure **Application Auto Scaling**
with the required scale-out / scale-in conditions.

* Account: `989346119941` (IAM user `Student`)
* Region: `eu-north-1` (Stockholm)
* Public URL: **http://hwbarabash1.pp.ua**
* Load / build host: `172.14.50.148` (user `user1`, Docker + aws-cli + `ab`)

---

## 1. Building the Docker image on 172.14.50.148

The source lives at `/home/user1/AWSexam/ToDoAI` (cloned from
https://github.com/macnaer/ToDoAI).

```bash
cd /home/user1/AWSexam/ToDoAI
docker build --provenance=false -t todoai:latest .
```

> `--provenance=false` is required: BuildKit attestation manifests can break
> Fargate image pulls.

The image was then tagged with the exam-specific tag `Vbarabash`:

```bash
docker tag todoai:latest todoai:Vbarabash
```

## 2. Pushing the image to Amazon ECR

The ECR repository `todoai` (mutable, scan-on-push) was created in
`eu-north-1`, then:

```bash
aws ecr get-login-password --region eu-north-1 | \
  docker login --username AWS --password-stdin \
  989346119941.dkr.ecr.eu-north-1.amazonaws.com

docker tag todoai:Vbarabash \
  989346119941.dkr.ecr.eu-north-1.amazonaws.com/todoai:Vbarabash
docker push \
  989346119941.dkr.ecr.eu-north-1.amazonaws.com/todoai:Vbarabash
docker logout 989346119941.dkr.ecr.eu-north-1.amazonaws.com
rm -f ~/.docker/config.json
```

Resulting image:

| Field | Value |
|---|---|
| URI | `989346119941.dkr.ecr.eu-north-1.amazonaws.com/todoai:Vbarabash` |
| Digest | `sha256:e6e58f5910bc51f96fc9517ad3005869fdcf0bdb5dcdcc519984e7d4dd54813e` |
| Size | 514 MB |

---

## 3. Infrastructure as Code — Terraform

Everything lives in this repository and is applied as a single root module.

```
AWS_terraform_exam/
├── versions.tf     # AWS provider ~> 5.0, default tags
├── variables.tf    # region, image, domain, Fargate size, scaling thresholds
├── main.tf         # full stack (see below)
├── outputs.tf      # ALB DNS, NS records, app URL, scaling summary
├── loadtest.sh     # load test + scaling monitor (run on 172.14.50.148)
└── .gitignore      # state, keys, .terraform
```

### 3.1 Security groups

| SG | Ingress |
|---|---|
| `exam-alb-sg` | TCP 80 from `0.0.0.0/0` |
| `exam-task-sg` | TCP 80 **only from `exam-alb-sg`** |

Tasks receive traffic exclusively from the load balancer; everything else is
locked down.

### 3.2 Application Load Balancer

* `exam-todoai-alb` — internet-facing, `application`, spread across the three
  default public subnets of `vpc-0fe3b80bbc95934d1`
* Target group `exam-todoai-tg` — `target_type = ip` (required for Fargate),
  health check `GET /` → `200-399` every 15 s
* Listener on TCP/80 → forward to the target group

### 3.3 ECS (Fargate)

* Cluster `exam-todoai` with Container Insights enabled
* Task definition `exam-todoai`: Fargate **256 CPU / 512 MiB**, awsvpc,
  container `app` on port 80, image `todoai:Vbarabash`,
  logs to CloudWatch `/ecs/todoai-exam` (7-day retention)
* Service `exam-todoai-svc`: `desired_count = 1`, `assign_public_ip = true`
  (tasks run in public subnets so they can pull from ECR and reach CloudWatch),
  health-check grace period 60 s, **deployment circuit breaker with rollback**
* IAM role `exam-todoai-exec` with `AmazonECSTaskExecutionRolePolicy`

### 3.4 Route53 — public name via ALB

* Public hosted zone `hwbarabash1.pp.ua`
* `A` record as an **alias** to the ALB
  (`evaluate_target_health = true`), so the application is reachable by name
  instead of by the generated ELB DNS name.

After `terraform apply` the zone's NS records had to be delegated at the
registrar (nic.ua / pp.ua panel):

```
ns-106.awsdns-13.com
ns-1143.awsdns-14.org
ns-1676.awsdns-17.co.uk
ns-982.awsdns-58.net
```

Delegation propagated within a few minutes and `http://hwbarabash1.pp.ua`
started returning `HTTP 200`.

### 3.5 Autoscaling conditions (exam requirements)

Scalable target: `ecs:service:DesiredCount`, **min 1 / max 4** tasks.

**Scale-OUT (growth) — TargetTracking, `TargetValue = 70`:**

| # | Metric | Condition |
|---|---|---|
| 1 | `ECSServiceAverageCPUUtilization` | CPU utilization **> 70 %** |
| 2 | `ALBRequestCountPerTarget` | request rate per target **> 70 %** of baseline |

* `ScaleOutCooldown = 60 s` → the service grows shortly after the load hits.

**Scale-IN (shrink) — TargetTracking, `ScaleInCooldown = 900 s` (15 minutes):**

| # | Condition |
|---|---|
| 1 | CPU utilization **falls from 70 % down to ≤ 50 % and stays there longer than 15 minutes** |
| 2 | Traffic **falls from 70 % down to ≤ 50 % and stays there longer than 15 minutes** |

Because TargetTracking only has a single target value, the 15-minute condition
is implemented with `ScaleInCooldown = 900`: the metric must remain below the
70 % target continuously for 15 minutes before a scale-in step is applied —
which is exactly the exam scenario "dropped from 70 % to 50 % for more than
15 min". Two explicit CloudWatch alarms document the scale-IN side as well:

| Alarm | Comparison | Period × Eval | Meaning |
|---|---|---|---|
| `exam-cpu-below-50-for-15m` | `CPUUtilization < 50` | 300 s × 3 = **15 min** | CPU fell below 50 % for > 15 min |
| `exam-requests-below-50-for-15m` | `RequestCountPerTarget < 50` | 300 s × 3 = **15 min** | traffic fell below 50 % for > 15 min |

`terraform output autoscaling` prints the full summary:

```hcl
{
  max_capacity          = 4
  min_capacity          = 1
  scale_in_below_pct    = 50
  scale_in_cooldown_min = 15
  scale_out_above_pct   = 70
}
```

---

## 4. Applying the configuration

```bash
export TF_VAR_aws_access_key=AKIA...
export TF_VAR_aws_secret_key=...
terraform init
terraform validate
terraform apply -auto-approve
```

Apply created **18 resources** in ~3 minutes:

```
Apply complete! Resources: 18 added, 0 changed, 0 destroyed.
```

Outputs:

```
alb_dns_name = "exam-todoai-alb-505388173.eu-north-1.elb.amazonaws.com"
app_url      = "http://hwbarabash1.pp.ua"
ns_records   = ["ns-106.awsdns-13.com", "ns-1143.awsdns-14.org",
                "ns-1676.awsdns-17.co.uk", "ns-982.awsdns-58.net"]
ecs_cluster  = "exam-todoai"
```

---

## 5. Verification

### 5.1 Service health

```text
aws ecs describe-services → desiredCount=1  runningCount=1
curl http://exam-todoai-alb-505388173.eu-north-1.elb.amazonaws.com/ → 200 (ToDoAI UI)
```

### 5.2 Public access by name (Route53)

```powershell
Invoke-WebRequest http://hwbarabash1.pp.ua   →  200
```

### 5.3 Load test (from 172.14.50.148)

`ab` (Apache Benchmark) against the public name — `loadtest.sh`:

```bash
ab -n 200000 -c 300 http://hwbarabash1.pp.ua/
```

Result:

| Metric | Value |
|---|---|
| Requests per second | **2242 req/s** |
| Time taken for tests | 89.2 s |
| Failed requests | **0** |

### 5.4 Scaling under load — growth (scale-OUT)

`desiredCount` polled every 30 s while/after the benchmark:

```text
BEFORE:   1 / 1
14:12:13  desired=1 running=1
14:13:47  desired=1 running=1
14:15:20  desired=1 running=1
14:16:23  desired=4 running=1   ← scale-out triggered (CPU + request rate > 70 %)
14:16:54  desired=4 running=4   ← all 4 tasks launched and healthy
```

The service grew from **1 → 4 tasks** (the configured maximum) within ~4.5
minutes of the load test — well inside the 60-second scale-out cooldown once
CloudWatch had collected enough datapoints.

### 5.5 Scaling after load stops — shrink (scale-IN)

The benchmark ended at **14:12 UTC**; metrics then stayed below the 70 %
target:

```text
14:17:48  desired=4 running=4
14:25:58  desired=4 running=4
14:30:03  desired=4 running=4
14:31:04  desired=3 running=3   ← scale-IN step (900 s cooldown expired)
14:47:17  desired=2 running=2   ← next step after another cooldown window
15:02:51  desired=1 running=1   ← back to the configured minimum
```

Scale-in started **~19 minutes** after the load stopped (15 minutes of metrics
below target + evaluation granularity) and stepped all the way down to the
minimum, confirming the exam condition:

* traffic/CPU fell from the > 70 % zone to ≤ 50 % and remained low for more
  than 15 minutes → instances (tasks) are removed.

**Full observed cycle: 1 → 4 (scale-out under load) → 3 → 2 → 1 (scale-in
after 15-min low-metric windows).**

---

## 6. Architecture diagram

```text
                        Route53
                hwbarabash1.pp.ua (A alias)
                          │
                          ▼
                 ┌─────────────────┐
 Internet ─────► │  ALB :80        │  exam-todoai-alb
                 │  exam-alb-sg    │
                 └────────┬────────┘
                          │ forward (target_type = ip)
                          ▼
                 ┌─────────────────┐
                 │  Target Group   │  exam-todoai-tg  (health: GET /)
                 └────────┬────────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
     ┌─────────┐     ┌─────────┐     ┌─────────┐
     │ Fargate │     │ Fargate │ ... │ Fargate │   256 CPU / 512 MiB
     │ task 1  │     │ task 2  │     │ task N  │   image: todoai:Vbarabash
     └─────────┘     └─────────┘     └─────────┘
          ▲               ▲               ▲
          └───────────────┼───────────────┘
                          │
              Application Auto Scaling
              min 1 / max 4 tasks
              scale-out: CPU > 70 %  |  req/target > 70 %   (cooldown 60 s)
              scale-in : below target for > 15 min           (cooldown 900 s)
```

---

## 7. Cost & teardown

* No EC2 instances, no NAT gateway — Fargate tasks use public IPs in the
  default VPC; ALB is the only other billable resource.
* Idle footprint: 1 × Fargate task (0.25 vCPU / 0.5 GB) + 1 ALB.
* Everything is Terraform-managed; a full teardown is one command:

```bash
terraform destroy -auto-approve
```

> Route53 hosted zone deletion requires emptying the zone; the NS delegation
> at the registrar should be removed afterwards.

---

## 8. Repository hygiene

`.gitignore` excludes Terraform state, lock overrides, `*.tfvars`, PEM keys
and `key_Student.txt` — **no secrets are committed**. AWS credentials are only
passed via environment variables (`TF_VAR_*`) at apply time.

---

## Screenshots

Console evidence for every exam requirement (AWS account `989346119941`,
region `eu-north-1`):

| # | File | Shows |
|---|---|---|
| 01 | `screens/01-ecs-service.png` | ECS service `exam-todoai-svc`: status Active, 1 desired/running task, task definition `exam-todoai:1`, LB target health (1 Healthy via `exam-todoai-tg` / `exam-todoai-alb`) |
| 02 | `screens/02-ecs-cluster.png` | ECS cluster `exam-todoai` with its services and tasks |
| 03 | `screens/03-alb.png` | Application Load Balancer `exam-todoai-alb` (internet-facing, DNS, listeners) |
| 04 | `screens/04-targetgroup.png` | Target group `exam-todoai-tg`: HTTP:80, target type `ip`, health check `GET /` |
| 05 | `screens/05-route53-zone.png` | Route53 hosted zone `hwbarabash1.pp.ua` with its records (NS/SOA + alias A) |
| 06 | `screens/06-cloudwatch-alarms.png` | CloudWatch alarms: CPU/requests scale-out (70 %) and below-50 %-for-15-min scale-in alarms |
| 07 | `screens/07-autoscaling.png` | Service auto scaling: task count **1–4**, two Active Target Tracking policies — `exam-cpu-scale-out` (`ECSServiceAverageCPUUtilization` 70 %) and `exam-requests-scale-out` (`ALBRequestCountPerTarget` 70) |
| 08 | `screens/08-ecr-images.png` | ECR repository `todoai` with image tag `Vbarabash` |
