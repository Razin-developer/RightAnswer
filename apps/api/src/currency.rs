//! Minimal currency conversion for the credit top-up flow. Only INR is
//! actually charged today (this app's one real market), but the shape
//! (a per-currency rate to USD) is deliberately ready for more currencies
//! later without changing any call site — just add a row here.
//!
//! Rates are fixed, not live-fetched: this is a mock payment system with
//! no real payment gateway behind it, so a live FX feed would be a lot of
//! moving parts for a number nothing actually settles against. Update the
//! constant when it drifts too far from reality.

/// Units of INR per 1 USD.
const INR_PER_USD: f64 = 96.57;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Currency {
    Inr,
}

impl Currency {
    pub fn from_code(code: &str) -> Option<Self> {
        match code.to_ascii_uppercase().as_str() {
            "INR" => Some(Currency::Inr),
            _ => None,
        }
    }

    fn per_usd(self) -> f64 {
        match self {
            Currency::Inr => INR_PER_USD,
        }
    }
}

/// Converts a USD amount into whole units of `currency`, rounded to the
/// nearest unit (INR has no meaningful sub-unit for a price display here).
pub fn usd_to_minor_units(usd: f64, currency: Currency) -> i64 {
    (usd * currency.per_usd()).round() as i64
}
