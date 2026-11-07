set -e
export AWS_DEFAULT_REGION=eu-north-1
echo "=== BEFORE ==="
aws ecs describe-services --cluster exam-todoai --services exam-todoai-svc --query 'services[0].[desiredCount,runningCount]' --output text
echo "=== LOAD START ==="
date -u
ab -n 200000 -c 300 http://hwbarabash1.pp.ua/ 2>&1 | grep -E "Requests per|Time taken|Failed requests|Non-2xx"
date -u
echo "=== MONITOR 30s x 10 ==="
for i in $(seq 1 10); do
  S=$(aws ecs describe-services --cluster exam-todoai --services exam-todoai-svc --query 'services[0].[desiredCount,runningCount]' --output text)
  echo "$(date -u +%H:%M:%S) $S"
  sleep 30
done
echo "=== SCALING ACTIVITIES ==="
aws application-autoscaling describe-scaling-activities --service-namespace ecs --resource-id service/exam-todoai/exam-todoai-svc --max-items 5 --query 'ScalingActivities[].[StatusCode,Reason]' --output text
