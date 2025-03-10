
function sjump() {
    # Get running jobs with detailed information
    # %i=jobid, %j=name, %N=nodelist, %M=time, %t=state, %R=reason
    jobs=$(squeue -u $USER -h -o "%i %j %N %M %t %R")
    
    if [ -z "$jobs" ]; then
        echo "No running jobs found"
        return 1
    fi
    
    # If there's only one job, use it directly
    if [ $(echo "$jobs" | wc -l) -eq 1 ]; then
        job_id=$(echo "$jobs" | awk '{print $1}')
        node=$(echo "$jobs" | awk '{print $3}' | cut -d',' -f1)
    else
        # Display jobs with numbers and formatted details
        echo "Multiple jobs found:"
        printf "\n%4s %-12s %-20s %-20s %-10s %-8s %s\n" \
               "Num" "JobID" "Name" "Nodes" "Time" "State" "Reason"
        echo "--------------------------------------------------------------------------------"
        
        echo "$jobs" | \
        awk '{printf "%4d %-12s %-20s %-20s %-10s %-8s %s\n", NR, $1, $2, $3, $4, $5, $6}' 
        
        echo -e "\nSelect job number:"
        read selection
        
        # Get the job details for selected number
        job_id=$(echo "$jobs" | sed -n "${selection}p" | awk '{print $1}')
        node=$(echo "$jobs" | sed -n "${selection}p" | awk '{print $3}' | cut -d',' -f1)
    fi
    
    # Save current working directory
    CURRENT_DIR=$(pwd)
    
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
    
    # Check if directory exists on remote node without hanging
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$node" "[ -d \"$CURRENT_DIR\" ]" 2>/dev/null; then
        echo "Maintaining current directory: $CURRENT_DIR"
        # First ensure any known host issues are resolved
        ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$node" &>/dev/null 2>&1
        # Connect with the directory change command
        ssh -o StrictHostKeyChecking=no -t "$node" "cd \"$CURRENT_DIR\" && bash"
    else
        echo "Current directory not found on remote node, using home directory"
        # Attempt SSH connection without directory change
        try_ssh "$node"
    fi
}
