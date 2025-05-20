-- Bảng Metadata: cdp_id_resolution_status
-- Bảng này dùng để theo dõi trạng thái và thời gian cuối cùng chạy của stored procedure chính

-- Drop the old table if it exists
DROP TABLE IF EXISTS cdp_id_resolution_status;

-- Create the new optimized table for concurrent tasks in cdp_id_resolution_status
CREATE TABLE cdp_id_resolution_status (
    -- Use BIGSERIAL for a simple, auto-incrementing primary key.
    -- This is very efficient for selecting/claiming the next task.
    id BIGSERIAL PRIMARY KEY,

    tenant_id VARCHAR(36) NOT NULL, 

    data_from_datetime TIMESTAMP WITH TIME ZONE NOT NULL,
    data_to_datetime TIMESTAMP WITH TIME ZONE NOT NULL,

    -- Status of the processing job for this specific time range and tenant
    job_status VARCHAR(12) NOT NULL DEFAULT 'pending', -- valid value: 'pending', 'processing', 'success', 'failed'
    processed_count INTEGER DEFAULT 0,

    job_started_at TIMESTAMP WITH TIME ZONE, -- When a worker claimed this task
    job_completed_at TIMESTAMP WITH TIME ZONE, -- When processing finished
    error_message TEXT, -- Store error details if job_status is 'failed'

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Add a unique constraint if the combination of tenant, from, and to should be unique
-- This prevents the same task (for the same tenant and time range) from being queued multiple times.
ALTER TABLE cdp_id_resolution_status
ADD CONSTRAINT uq_cdp_id_resolution_status_tenant_range UNIQUE (tenant_id, data_from_datetime, data_to_datetime);

-- Add indexes for efficient querying of pending tasks and by tenant
-- The primary key 'id' is automatically indexed.
CREATE INDEX idx_cdp_id_resolution_status_status_from_dt ON cdp_id_resolution_status (job_status, data_from_datetime);
CREATE INDEX idx_cdp_id_resolution_status_tenant_id ON cdp_id_resolution_status (tenant_id);

-- Optional: Index on job_started_at to find stalled tasks
CREATE INDEX idx_cdp_id_resolution_status_job_started_at ON cdp_id_resolution_status (job_started_at, job_status);

-- Optional: Add a function to update the updated_at column automatically
CREATE OR REPLACE FUNCTION set_id_resolution_status_updated()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$ language 'plpgsql';

-- Add a trigger to call the function before update
CREATE TRIGGER trigger_set_id_resolution_status_updated
BEFORE UPDATE
ON cdp_id_resolution_status
FOR EACH ROW
EXECUTE PROCEDURE set_id_resolution_status_updated();

