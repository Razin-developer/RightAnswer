/// Minimal currency conversion for the credit top-up flow — mirrors
/// apps/api/src/currency.rs so the amount shown client-side always matches
/// what the server actually charges. Only INR is live today (fixed rate,
/// not fetched — this is a mock payment system with no real gateway
/// behind it), but the shape (a per-currency rate to USD) is ready for
/// more currencies without changing any call site.
class Currency {
  final String code;
  final String symbol;
  final double perUsd;

  const Currency._(this.code, this.symbol, this.perUsd);

  static const inr = Currency._('INR', '₹', 96.57);

  static const all = [inr];

  double usdToLocal(double usd) => usd * perUsd;

  /// Rounded to the nearest whole unit — matches the server's
  /// usd_to_minor_units, which also rounds rather than truncates.
  int usdToLocalRounded(double usd) => usdToLocal(usd).round();
}
