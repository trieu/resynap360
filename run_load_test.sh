#!/bin/bash

# === CONFIG ===
TESTCASE="test_cases/test_with_fake_data.py"
HOST="https://cdp-api.stage.pnj.io"
MASTER_HOST="127.0.0.1"
WORKER_COUNT=3

start_master() {
  echo "Starting Locust master..."
  nohup locust -f $TESTCASE \
    --master \
    --expect-workers $WORKER_COUNT \
    --host=$HOST \
    --loglevel=INFO > logs/locust_master.log 2>&1 &
  echo "Locust master started with PID $!"
}

start_workers() {
  echo "Starting $WORKER_COUNT Locust workers..."
  for i in $(seq 1 $WORKER_COUNT); do
    nohup locust -f $TESTCASE \
      --worker \
      --master-host=$MASTER_HOST \
      --loglevel=INFO > logs/locust_worker_$i.log 2>&1 &
    echo "Worker $i started with PID $!"
  done
}

start_single_node() {
  pkill -f "locust"
  sleep 1
  echo "Starting Locust in single-node mode..."
  nohup locust -f $TESTCASE \
    --host=$HOST \
    --loglevel=INFO > logs/locust_single_node.log 2>&1 &
  echo "Locust single-node started with PID $!"
}

stop_locust() {
  echo "Stopping all Locust processes..."
  pkill -f "locust"
  echo "All Locust processes stopped."
}

case "$1" in
  start)
    mkdir -p logs
    start_master
    start_workers
    ;;
  start_single)
    mkdir -p logs
    start_single_node
    ;;
  stop)
    stop_locust
    ;;
  *)
    echo "Usage: $0 {start|start_single|stop}"
    ;;
esac
