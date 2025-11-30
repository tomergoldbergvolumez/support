#!/usr/bin/env bash
# measure_all_regions.sh
# Run latency measurements across ALL AWS regions
# Usage: ./measure_all_regions.sh [ssh-key-path]
# Compatible with Bash 3.2+ (macOS default)

set -e

SSH_KEY=${1:-~/.ssh/aws-key.pem}

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
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="./results_$TIMESTAMP"
INSTANCE_TYPE="t3.micro"
PING_COUNT=100

# All commercial AWS regions (update as needed)
REGIONS=(
    "us-east-1"
    "us-east-2"
    "us-west-1"
    "us-west-2"
    "ca-central-1"
    "eu-west-1"
    "eu-west-2"
    "eu-west-3"
    "eu-central-1"
    "eu-central-2"
    "eu-north-1"
    "eu-south-1"
    "eu-south-2"
    "ap-south-1"
    "ap-south-2"
    "ap-northeast-1"
    "ap-northeast-2"
    "ap-northeast-3"
    "ap-southeast-1"
    "ap-southeast-2"
    "ap-southeast-3"
    "ap-southeast-4"
    "ap-east-1"
    "sa-east-1"
    "me-south-1"
    "me-central-1"
    "af-south-1"
)

mkdir -p "$RESULTS_DIR"

echo "=============================================="
echo "AWS Full-Mesh Inter-AZ Latency Measurement"
echo "Timestamp: $TIMESTAMP"
echo "Regions: ${#REGIONS[@]}"
echo "Results: $RESULTS_DIR"
echo "=============================================="

# Track all instances for cleanup (parallel arrays instead of associative arrays)
CLEANUP_REGIONS=()
CLEANUP_INSTANCES=()
CLEANUP_SGS=()

cleanup() {
    echo -e "\n[CLEANUP] Terminating all instances..."
    for i in "${!CLEANUP_REGIONS[@]}"; do
        REGION=${CLEANUP_REGIONS[$i]}
        INSTANCES=${CLEANUP_INSTANCES[$i]}
        if [ -n "$INSTANCES" ]; then
            echo "  $REGION: Terminating instances..."
            aws ec2 terminate-instances --region $REGION --instance-ids $INSTANCES > /dev/null 2>&1 || true
        fi
    done

    echo "  Waiting for termination..."
    sleep 30

    for i in "${!CLEANUP_REGIONS[@]}"; do
        REGION=${CLEANUP_REGIONS[$i]}
        SG_ID=${CLEANUP_SGS[$i]}
        if [ -n "$SG_ID" ]; then
            echo "  $REGION: Deleting security group..."
            aws ec2 delete-security-group --region $REGION --group-id $SG_ID 2>/dev/null || true
        fi
    done
    echo "Cleanup complete!"
}

trap cleanup EXIT

# Process each region
COMBINED_RESULTS='{"timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","regions":['
FIRST_REGION=true

for REGION in "${REGIONS[@]}"; do
    echo -e "\n====== Processing: $REGION ======"
    
    # Check if region is enabled
    if ! aws ec2 describe-availability-zones --region $REGION > /dev/null 2>&1; then
        echo "  Region not enabled, skipping..."
        continue
    fi
    
    # Get AZs
    AZS=$(aws ec2 describe-availability-zones \
        --region $REGION \
        --filters "Name=opt-in-status,Values=opt-in-not-required" \
        --query 'AvailabilityZones[].{Name:ZoneName,Id:ZoneId}' \
        --output json 2>/dev/null || echo "[]")
    
    AZ_COUNT=$(echo "$AZS" | jq length)
    if [ "$AZ_COUNT" -lt 2 ]; then
        echo "  Less than 2 AZs, skipping..."
        continue
    fi
    
    echo "  Found $AZ_COUNT AZs"
    
    # Get AMI
    AMI_ID=$(aws ec2 describe-images \
        --region $REGION \
        --owners amazon \
        --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text 2>/dev/null)
    
    if [ -z "$AMI_ID" ] || [ "$AMI_ID" == "None" ]; then
        echo "  No suitable AMI found, skipping..."
        continue
    fi
    
    # Create security group
    VPC_ID=$(aws ec2 describe-vpcs --region $REGION --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
    
    SG_NAME="latency-test-$TIMESTAMP"
    SG_ID=$(aws ec2 create-security-group \
        --region $REGION \
        --group-name "$SG_NAME" \
        --description "Latency testing" \
        --vpc-id $VPC_ID \
        --query 'GroupId' \
        --output text 2>/dev/null || echo "")
    
    CURRENT_SG=""
    if [ -n "$SG_ID" ]; then
        CURRENT_SG=$SG_ID
        aws ec2 authorize-security-group-ingress --region $REGION --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 2>/dev/null || true
        aws ec2 authorize-security-group-ingress --region $REGION --group-id $SG_ID --protocol icmp --port -1 --cidr 0.0.0.0/0 2>/dev/null || true
    fi

    # Launch instances (parallel arrays instead of associative arrays)
    AZ_IDS=()
    INSTANCE_IDS=()
    PRIVATE_IPS=()
    PUBLIC_IPS=()
    INSTANCES=""

    for AZ_DATA in $(echo "$AZS" | jq -c '.[]'); do
        AZ_NAME=$(echo $AZ_DATA | jq -r '.Name')
        AZ_ID=$(echo $AZ_DATA | jq -r '.Id')

        INSTANCE_ID=$(aws ec2 run-instances \
            --region $REGION \
            --image-id $AMI_ID \
            --instance-type $INSTANCE_TYPE \
            --key-name $(basename $SSH_KEY .pem) \
            --security-group-ids $SG_ID \
            --placement "AvailabilityZone=$AZ_NAME" \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=latency-test-$AZ_ID}]" \
            --query 'Instances[0].InstanceId' \
            --output text 2>/dev/null || echo "")

        if [ -n "$INSTANCE_ID" ]; then
            INSTANCES="$INSTANCES $INSTANCE_ID"
            AZ_IDS+=("$AZ_ID")
            INSTANCE_IDS+=("$INSTANCE_ID")
            echo "    Launched $AZ_ID: $INSTANCE_ID"
        fi
    done

    # Track for cleanup
    CLEANUP_REGIONS+=("$REGION")
    CLEANUP_INSTANCES+=("$INSTANCES")
    CLEANUP_SGS+=("$CURRENT_SG")
    
    # Wait for instances
    if [ -n "$INSTANCES" ]; then
        echo "  Waiting for instances to be running..."
        aws ec2 wait instance-running --region $REGION --instance-ids $INSTANCES 2>/dev/null || true
        sleep 10
        
        # Get IPs
        for i in "${!AZ_IDS[@]}"; do
            INSTANCE_ID=${INSTANCE_IDS[$i]}
            IPS=$(aws ec2 describe-instances \
                --region $REGION \
                --instance-ids $INSTANCE_ID \
                --query 'Reservations[0].Instances[0].{Private:PrivateIpAddress,Public:PublicIpAddress}' \
                --output json 2>/dev/null || echo '{}')

            PRIVATE_IPS[$i]=$(echo $IPS | jq -r '.Private // empty')
            PUBLIC_IPS[$i]=$(echo $IPS | jq -r '.Public // empty')
        done
        
        # Wait for SSH
        sleep 20
        
        # Run measurements
        echo "  Running measurements..."
        REGION_RESULTS='{"region":"'$REGION'","measurements":['
        FIRST_MEASUREMENT=true

        for ((i=0; i<${#AZ_IDS[@]}; i++)); do
            for ((j=i+1; j<${#AZ_IDS[@]}; j++)); do
                SRC_AZ=${AZ_IDS[$i]}
                DST_AZ=${AZ_IDS[$j]}
                SRC_PUBLIC=${PUBLIC_IPS[$i]}
                DST_PRIVATE=${PRIVATE_IPS[$j]}
                
                if [ -z "$SRC_PUBLIC" ] || [ -z "$DST_PRIVATE" ]; then
                    continue
                fi
                
                PING_OUTPUT=$(timeout 30 ssh -i $SSH_KEY \
                    -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    -o ConnectTimeout=10 \
                    -o LogLevel=ERROR \
                    ec2-user@$SRC_PUBLIC \
                    "ping -c $PING_COUNT -i 0.05 -q $DST_PRIVATE" 2>/dev/null || echo "FAILED")
                
                if [[ "$PING_OUTPUT" == *"rtt"* ]]; then
                    STATS=$(echo "$PING_OUTPUT" | grep "rtt" | awk -F'=' '{print $2}' | awk -F'/' '{print $1","$2","$3","$4}')
                    MIN=$(echo $STATS | cut -d',' -f1 | tr -d ' ')
                    AVG=$(echo $STATS | cut -d',' -f2 | tr -d ' ')
                    MAX=$(echo $STATS | cut -d',' -f3 | tr -d ' ')
                    MDEV=$(echo $STATS | cut -d',' -f4 | tr -d ' ms')
                    
                    echo "    $SRC_AZ <-> $DST_AZ: ${AVG}ms"
                    
                    if [ "$FIRST_MEASUREMENT" = true ]; then
                        FIRST_MEASUREMENT=false
                    else
                        REGION_RESULTS="$REGION_RESULTS,"
                    fi
                    
                    REGION_RESULTS="$REGION_RESULTS"'{"source_az":"'$SRC_AZ'","target_az":"'$DST_AZ'","min_ms":'$MIN',"avg_ms":'$AVG',"max_ms":'$MAX',"mdev_ms":'$MDEV'}'
                fi
            done
        done
        
        REGION_RESULTS="$REGION_RESULTS]}"
        
        # Save region results
        echo "$REGION_RESULTS" > "$RESULTS_DIR/${REGION}.json"
        
        # Add to combined results
        if [ "$FIRST_REGION" = true ]; then
            FIRST_REGION=false
        else
            COMBINED_RESULTS="$COMBINED_RESULTS,"
        fi
        COMBINED_RESULTS="$COMBINED_RESULTS$REGION_RESULTS"
    fi
    
done

COMBINED_RESULTS="$COMBINED_RESULTS]}"

# Save combined results
echo "$COMBINED_RESULTS" | jq '.' > "$RESULTS_DIR/all_regions.json"

echo -e "\n=============================================="
echo "COMPLETE!"
echo "Results saved to: $RESULTS_DIR/"
echo "=============================================="

# Generate summary
echo -e "\nSUMMARY:"
cat "$RESULTS_DIR/all_regions.json" | jq -r '
.regions[] | 
"  \(.region):" + 
(.measurements | map("    \(.source_az) <-> \(.target_az): \(.avg_ms)ms") | join("\n"))
'
