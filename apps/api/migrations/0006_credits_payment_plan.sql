-- Standalone AI-credit top-ups (routes::plans_checkout `plan: "credits"`)
-- create a payments row too, but the original CHECK constraint only ever
-- allowed 'pro'/'scholar' — a top-up isn't a plan-tier purchase and was
-- rejected outright.
ALTER TABLE payments DROP CONSTRAINT payments_plan_check;
ALTER TABLE payments ADD CONSTRAINT payments_plan_check
  CHECK (plan IN ('pro', 'scholar', 'credits'));
