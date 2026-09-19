#!/bin/bash
for j in 122581012 122581013 122581018 122581024 122580999 122581008 122581010; do
    scancel $j && echo "canceled $j"
done
echo "remaining RUNNING/PENDING:"
squeue -u "$USER" -t RUNNING,PENDING -h | wc -l