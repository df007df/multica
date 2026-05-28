-- Repair any project rows whose status/priority fell outside the allowed enum.
-- This can happen from manual DB edits, failed migrations, or data imports.
-- Map unknown values to the closest valid equivalent so the frontend never
-- crashes on enum drift.

-- Fix unknown status values: map to 'planned' (the default)
UPDATE project
SET status = 'planned'
WHERE status NOT IN ('planned', 'in_progress', 'paused', 'completed', 'cancelled');

-- Fix unknown priority values: map to 'none' (the default)
UPDATE project
SET priority = 'none'
WHERE priority NOT IN ('urgent', 'high', 'medium', 'low', 'none');
