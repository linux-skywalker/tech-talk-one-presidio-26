# Plain-English names for the run's own log lines (video only).
s/submitted serve \(team a, [0-9]+ units, priority inference\)/Inference server starts (Team A)/
s/submitted a[13] \(trainm, team a, [0-9]+ units?\)/Team A submits a medium training job/
s/submitted a2 \(trains, team a, [0-9]+ units?\)/Team A submits a small training job/
s/submitted b2 \(trainm, team b, [0-9]+ units?\)/Team B submits a medium training job/
s/submitted b[13] \(trains, team b, [0-9]+ units?\)/Team B submits a small training job/
s/jobs done ([0-9]+), failed ([0-9]+) of 6; Running=([0-9]+)/jobs finished: \1 of 6, crashed for good: \2, pods running: \3/
/^  (scenario|arm|rep|duration_s|queue_wait_s|wait_train_median_s|wait_train_max_s|wait_team_A_max_s|wait_team_B_max_s|jobs_total|jobs_per_hour|restarts_serve|preempted_workloads|evictions|gpu_util_avg|gpu_mem_max_mib|dcgm_avg_util|waiting_job_seconds|waiting_while_mem_below_9GB_s|waiting_while_util_below_50_s|unit_seconds_A|unit_seconds_B|share_A_pct|probe_ok|probe_err|ttft_p50_s|ttft_p95_s) /d
s/^  jobs_done +([^ ]+)/  jobs finished (of 6)              \1/
s/^  jobs_failed +([^ ]+)/  jobs that never finished          \1/
s/^  pods_failed +([^ ]+)/  crashed pods                      \1/
s/^  pods_with_oom +([^ ]+)/  of those, out of GPU memory       \1/
s/^  makespan_s +([^ ]+)/  last job finished at (s)          \1/
s/^  latency_p95_s +([^ ]+)/  server reply time p95 (s)         \1/
