-- Create deactivation_requests table for tracking device admin deactivation requests
CREATE TABLE IF NOT EXISTS deactivation_requests (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    requested_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    commitment_end_date TIMESTAMP WITH TIME ZONE NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'cancelled')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Create index on user_id for faster lookups
CREATE INDEX IF NOT EXISTS idx_deactivation_requests_user_id ON deactivation_requests(user_id);

-- Create index on status for filtering
CREATE INDEX IF NOT EXISTS idx_deactivation_requests_status ON deactivation_requests(status);

-- Create index on requested_at for time-based queries
CREATE INDEX IF NOT EXISTS idx_deactivation_requests_requested_at ON deactivation_requests(requested_at);

-- Add trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_deactivation_requests_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_deactivation_requests_updated_at
    BEFORE UPDATE ON deactivation_requests
    FOR EACH ROW
    EXECUTE FUNCTION update_deactivation_requests_updated_at();
