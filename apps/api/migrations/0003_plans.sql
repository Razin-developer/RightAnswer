ALTER TABLE users
  ADD COLUMN IF NOT EXISTS plan TEXT NOT NULL DEFAULT 'hobby'
    CHECK (plan IN ('hobby', 'pro', 'scholar')),
  ADD COLUMN IF NOT EXISTS credit_balance_usd DOUBLE PRECISION NOT NULL DEFAULT 0;

-- Mock payment records for the plan checkout flow. `status` starts
-- 'pending' when checkout begins and is finalized by the (currently mock)
-- payment screen's Success/Failure buttons — see routes::complete_payment.
-- Kept as its own table (not just a field on users) so it scales cleanly to
-- a real payment gateway webhook later without a schema change.
CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan TEXT NOT NULL CHECK (plan IN ('pro', 'scholar')),
  amount_inr BIGINT NOT NULL,
  credits_usd DOUBLE PRECISION NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'success', 'failed')),
  provider TEXT NOT NULL DEFAULT 'mock',
  provider_ref TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_payments_user ON payments(user_id, created_at DESC);
