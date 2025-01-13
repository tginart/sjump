function sjump() {
    # Get running jobs with detailed information
    # %i=jobid, %j=name, %N=nodelist, %M=time, %t=state, %R=reason, %C=cpus
    jobs=$(squeue -u $USER -h -o "%i %j %N %M %t %R %C")
    
    if [ -z "$jobs" ]; then
        echo "No running jobs found"
        return 1
    }

    # Function to get resource utilization for a node
    function get_node_stats() {
        local node=$1
        # Get CPU usage (using top in batch mode)
        local cpu_usage=$(ssh -o StrictHostKeyChecking=no "$node" "top -bn1 | grep '%Cpu' | awk '{print \$2}'")
        # Get memory usage (using free)
        local mem_total=$(ssh -o StrictHostKeyChecking=no "$node" "free -g | grep Mem: | awk '{print \$2}'")
        local mem_used=$(ssh -o StrictHostKeyChecking=no "$node" "free -g | grep Mem: | awk '{print \$3}'")
        local mem_usage=$((mem_used * 100 / mem_total))
        # Try to get GPU usage if nvidia-smi exists
        local gpu_stats=$(ssh -o StrictHostKeyChecking=no "$node" "command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits" 2>/dev/null)
        
        echo "$cpu_usage|$mem_usage|$gpu_stats"
    }

    # Function to format resource stats
    function format_resources() {
        local nodelist=$1
        local resources=""
        local total_cpu=0
        local total_mem=0
        local node_count=0
        local gpu_stats=""

        # Expand nodelist if it contains ranges (e.g., node[1-3] to node1,node2,node3)
        local expanded_nodes=$(scontrol show hostnames "$nodelist")
        
        for node in $expanded_nodes; do
            local stats=$(get_node_stats "$node")
            IFS='|' read -r cpu mem gpu <<< "$stats"
            
            # Add to totals
            total_cpu=$(echo "$total_cpu + $cpu" | bc)
            total_mem=$(echo "$total_mem + $mem" | bc)
            node_count=$((node_count + 1))
            
            # If GPU stats available, process them
            if [ ! -z "$gpu" ]; then
                gpu_stats="$gpu"
            fi
        done
        
        # Calculate averages
        local avg_cpu=$(echo "scale=1; $total_cpu / $node_count" | bc)
        local avg_mem=$(echo "scale=1; $total_mem / $node_count" | bc)
        
        # Format the output
        resources="CPU: ${avg_cpu}% MEM: ${avg_mem}%"
        if [ ! -z "$gpu_stats" ]; then
            IFS=',' read -r gpu_util gpu_mem_used gpu_mem_total <<< "$gpu_stats"
            resources="$resources GPU: ${gpu_util}% (${gpu_mem_used}/${gpu_mem_total}MB)"
        fi
        
        echo "$resources"
    }
    
    # If there's only one job, use it directly
    if [ $(echo "$jobs" | wc -l) -eq 1 ]; then
        job_id=$(echo "$jobs" | awk '{print $1}')
        node=$(echo "$jobs" | awk '{print $3}' | cut -d',' -f1)
        resources=$(format_resources "$node")
        echo "Connecting to job $job_id on node $node"
        echo "Resource usage: $resources"
    else
        # Display jobs with numbers and formatted details
        printf "\n%4s %-12s %-15s %-15s %-10s %-8s %-40s\n" \
               "Num" "JobID" "Name" "Nodes" "Time" "State" "Resources"
        echo "----------------------------------------------------------------------------------------"
        
        # Process each job
        while IFS= read -r job_line; do
            job_num=$((job_num + 1))
            job_id=$(echo "$job_line" | awk '{print $1}')
            job_name=$(echo "$job_line" | awk '{print $2}')
            nodes=$(echo "$job_line" | awk '{print $3}')
            time=$(echo "$job_line" | awk '{print $4}')
            state=$(echo "$job_line" | awk '{print $5}')
            
            # Only get resources for running jobs
            if [ "$state" == "R" ]; then
                resources=$(format_resources "$nodes")
            else
                resources="N/A"
            fi
            
            printf "%4d %-12s %-15s %-15s %-10s %-8s %-40s\n" \
                   "$job_num" "$job_id" "$job_name" "$nodes" "$time" "$state" "$resources"
        done <<< "$jobs"
        
        echo -e "\nSelect job number:"
        read selection
        
        # Get the job details for selected number
        job_id=$(echo "$jobs" | sed -n "${selection}p" | awk '{print $1}')
        node=$(echo "$jobs" | sed -n "${selection}p" | awk '{print $3}' | cut -d',' -f1)
    fi
    
    # Function to attempt SSH with automatic host key handling
    function try_ssh() {
        local node=$1
        if ssh -o StrictHostKeyChecking=no "$node" 2>/dev/null; then
            return 0
        else
            # If SSH fails, try to remove the problematic key and retry
            ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$node" &>/dev/null
            ssh -o StrictHostKeyChecking=no "$node"
        fi
    }
    
    echo "Connecting to node $node for job $job_id..."
    # Attempt SSH connection
    try_ssh "$node"
}
