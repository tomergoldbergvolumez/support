#!/usr/bin/env bash
# quick_measure.sh
# Quick single-region full-mesh latency measurement
# Usage: ./quick_measure.sh <region> [ssh-key-path]
# Compatible with Bash 3.2+ (macOS default)

set -e

REGION=${1:-us-east-1}
SSH_KEY=${2:-~/.ssh/aws-key.pem}
INSTANCE_TYPE="t3.micro"
PING_COUNT=100

# Helper function to find index of a value in an array
# Usage: idx=$(get_index "value" "${array[@]}")
get_index() {
    local key=$1
    shift
    local i=0
    for val in "$@"; do
        if [[ "$val" == "$key" ]]; then
            echo "$i"
            return 0
        fi
        ((i++))
    done
    return 1
}

echo "=============================================="
echo "AWS Inter-AZ Latency Measurement"
echo "Region: $REGION"
echo "=============================================="

# Get all AZs in the region
echo -e "\n[1/5] Getting availability zones..."
AZS=$(aws ec2 describe-availability-zones \
    --region $REGION \
    --filters "Name=opt-in-status,Values=opt-in-not-required" \
    --query 'AvailabilityZones[].{Name:ZoneName,Id:ZoneId}' \
    --output json)

echo "Found AZs:"
echo "$AZS" | jq -r '.[] | "  \(.Id) (\(.Name))"'

AZ_COUNT=$(echo "$AZS" | jq length)
echo "Total: $AZ_COUNT availability zones"

# Get latest Amazon Linux 2023 AMI
echo -e "\n[2/5] Getting latest AMI..."
AMI_ID=$(aws ec2 describe-images \
    --region $REGION \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)
echo "AMI: $AMI_ID"

# Create security group
echo -e "\n[3/5] Creating security group..."
VPC_ID=$(aws ec2 describe-vpcs --region $REGION --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)

SG_ID=$(aws ec2 create-security-group \
    --region $REGION \
    --group-name "latency-test-$(date +%s)" \
    --description "Latency testing" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text 2>/dev/null || echo "")

if [ -z "$SG_ID" ]; then
    SG_ID=$(aws ec2 describe-security-groups \
        --region $REGION \
        --filters "Name=group-name,Values=latency-test-*" \
        --query 'SecurityGroups[0].GroupId' \
        --output text)
fi

# Add rules
aws ec2 authorize-security-group-ingress --region $REGION --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 2>/dev/null || true
aws ec2 authorize-security-group-ingress --region $REGION --group-id $SG_ID --protocol icmp --port -1 --cidr 0.0.0.0/0 2>/dev/null || true
echo "Security Group: $SG_ID"

# Launch instances in each AZ
echo -e "\n[4/5] Launching instances..."
INSTANCES=""
# Parallel arrays instead of associative arrays (Bash 3.2 compatible)
AZ_IDS=()
INSTANCE_IDS=()
PRIVATE_IPS=()
PUBLIC_IPS=()

for AZ_DATA in $(echo "$AZS" | jq -c '.[]'); do
    AZ_NAME=$(echo $AZ_DATA | jq -r '.Name')
    AZ_ID=$(echo $AZ_DATA | jq -r '.Id')

    echo "  Launching in $AZ_ID ($AZ_NAME)..."

    INSTANCE_ID=$(aws ec2 run-instances \
        --region $REGION \
        --image-id $AMI_ID \
        --instance-type $INSTANCE_TYPE \
        --key-name $(basename $SSH_KEY .pem) \
        --security-group-ids $SG_ID \
        --placement "AvailabilityZone=$AZ_NAME" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=latency-test-$AZ_ID},{Key=AZ_ID,Value=$AZ_ID}]" \
        --query 'Instances[0].InstanceId' \
        --output text)

    INSTANCES="$INSTANCES $INSTANCE_ID"
    AZ_IDS+=("$AZ_ID")
    INSTANCE_IDS+=("$INSTANCE_ID")
    echo "    Instance: $INSTANCE_ID"
done

# Wait for instances to be running
echo -e "\n  Waiting for instances to be running..."
aws ec2 wait instance-running --region $REGION --instance-ids $INSTANCES
echo "  All instances running!"

# Get IPs
echo -e "\n  Getting IP addresses..."
for i in "${!AZ_IDS[@]}"; do
    AZ_ID=${AZ_IDS[$i]}
    INSTANCE_ID=${INSTANCE_IDS[$i]}
    IPS=$(aws ec2 describe-instances \
        --region $REGION \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].{Private:PrivateIpAddress,Public:PublicIpAddress}' \
        --output json)

    PRIVATE_IPS[$i]=$(echo $IPS | jq -r '.Private')
    PUBLIC_IPS[$i]=$(echo $IPS | jq -r '.Public')
    echo "    $AZ_ID: Private=${PRIVATE_IPS[$i]}, Public=${PUBLIC_IPS[$i]}"
done

# Wait for SSH to be available
echo -e "\n  Waiting for SSH to be ready..."
sleep 30

# Run measurements
echo -e "\n[5/5] Running latency measurements..."
RESULTS_FILE="results_${REGION}_$(date +%Y%m%d_%H%M%S).json"
echo '{"region":"'$REGION'","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","results":[' > $RESULTS_FILE

FIRST=true
for ((i=0; i<${#AZ_IDS[@]}; i++)); do
    for ((j=i+1; j<${#AZ_IDS[@]}; j++)); do
        SRC_AZ=${AZ_IDS[$i]}
        DST_AZ=${AZ_IDS[$j]}
        SRC_PUBLIC=${PUBLIC_IPS[$i]}
        DST_PRIVATE=${PRIVATE_IPS[$j]}
        
        echo "  Measuring $SRC_AZ -> $DST_AZ..."
        
        # Run ping from source to destination
        PING_OUTPUT=$(ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR \
            ec2-user@$SRC_PUBLIC \
            "ping -c $PING_COUNT -i 0.05 -q $DST_PRIVATE" 2>/dev/null || echo "FAILED")
        
        if [[ "$PING_OUTPUT" == *"rtt"* ]]; then
            STATS=$(echo "$PING_OUTPUT" | grep "rtt" | awk -F'=' '{print $2}' | awk -F'/' '{print $1","$2","$3","$4}')
            MIN=$(echo $STATS | cut -d',' -f1 | tr -d ' ')
            AVG=$(echo $STATS | cut -d',' -f2 | tr -d ' ')
            MAX=$(echo $STATS | cut -d',' -f3 | tr -d ' ')
            MDEV=$(echo $STATS | cut -d',' -f4 | tr -d ' ms')
            
            echo "    Result: avg=${AVG}ms (min=$MIN, max=$MAX, mdev=$MDEV)"
            
            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                echo ',' >> $RESULTS_FILE
            fi
            
            echo '{"source_az":"'$SRC_AZ'","target_az":"'$DST_AZ'","min_ms":'$MIN',"avg_ms":'$AVG',"max_ms":'$MAX',"mdev_ms":'$MDEV'}' >> $RESULTS_FILE
        else
            echo "    FAILED"
        fi
    done
done

echo ']}' >> $RESULTS_FILE
echo -e "\n  Results saved to: $RESULTS_FILE"

# Print summary
echo -e "\n=============================================="
echo "SUMMARY - $REGION Inter-AZ Latencies"
echo "=============================================="
cat $RESULTS_FILE | jq -r '.results[] | "\(.source_az) <-> \(.target_az): \(.avg_ms)ms"'

# Cleanup prompt
echo -e "\n=============================================="
echo "CLEANUP"
echo "=============================================="
echo "To terminate instances and cleanup:"
echo "  aws ec2 terminate-instances --region $REGION --instance-ids $INSTANCES"
echo "  aws ec2 delete-security-group --region $REGION --group-id $SG_ID"
echo ""
read -p "Terminate instances now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Terminating instances..."
    aws ec2 terminate-instances --region $REGION --instance-ids $INSTANCES > /dev/null
    echo "Waiting for termination..."
    aws ec2 wait instance-terminated --region $REGION --instance-ids $INSTANCES
    echo "Deleting security group..."
    aws ec2 delete-security-group --region $REGION --group-id $SG_ID 2>/dev/null || true
    echo "Cleanup complete!"
fi

echo -e "\nDone!"
