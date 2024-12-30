## ADD THIS TO YOUR ~/.bashrc file

function sjump() {
    # Get running jobs and their node allocations
    jobs=$(squeue -u $USER -h -o "%i %N")
    
    if [ -z "$jobs" ]; then
        echo "No running jobs found"
        return 1
    fi
    
    # If there's only one job, use it directly
    if [ $(echo "$jobs" | wc -l) -eq 1 ]; then
        job_id=$(echo "$jobs" | awk '{print $1}')
        node=$(echo "$jobs" | awk '{print $2}' | cut -d',' -f1)
    else
        # Display jobs with numbers for selection
        echo "Multiple jobs found:"
        echo "$jobs" | nl
        echo "Select job number:"
        read selection
        
        # Get the job details for selected number
        job_id=$(echo "$jobs" | sed -n "${selection}p" | awk '{print $1}')
        node=$(echo "$jobs" | sed -n "${selection}p" | awk '{print $2}' | cut -d',' -f1)
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
    
    # Attempt SSH connection
    try_ssh "$node"
}
