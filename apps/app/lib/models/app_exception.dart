enum AppErrorType {
  configuration,
  network,
  authentication,
  rateLimit,
  service,
  validation,
  unknown,
  // The signed-in user's plan credit is exhausted (daily or weekly) — see
  // ApiError::LimitExceeded on the backend. Distinct from rateLimit (the
  // request-pacing governor, a transient "slow down" signal): this means
  // "come back later or upgrade", and carries when that "later" is.
  usageLimitExceeded,
}

class AppException implements Exception {
  final AppErrorType type;
  final String title;
  final String message;
  final DateTime? resetAt;

  const AppException({
    required this.type,
    required this.title,
    required this.message,
    this.resetAt,
  });

  factory AppException.configuration(String message) => AppException(
    type: AppErrorType.configuration,
    title: 'Configuration Required',
    message: message,
  );

  factory AppException.network(String message) => AppException(
    type: AppErrorType.network,
    title: 'Connection Problem',
    message: message,
  );

  factory AppException.authentication(String message) => AppException(
    type: AppErrorType.authentication,
    title: 'Authentication Failed',
    message: message,
  );

  factory AppException.rateLimit(String message) => AppException(
    type: AppErrorType.rateLimit,
    title: 'Too Many Requests',
    message: message,
  );

  factory AppException.service(String message) => AppException(
    type: AppErrorType.service,
    title: 'Service Error',
    message: message,
  );

  factory AppException.validation(String message) => AppException(
    type: AppErrorType.validation,
    title: 'Check Your Input',
    message: message,
  );

  factory AppException.unknown(String message) => AppException(
    type: AppErrorType.unknown,
    title: 'Something Went Wrong',
    message: message,
  );

  factory AppException.usageLimitExceeded(String message, DateTime? resetAt) =>
      AppException(
        type: AppErrorType.usageLimitExceeded,
        title: 'Limit Reached',
        message: message,
        resetAt: resetAt,
      );

  static AppException from(Object error) {
    if (error is AppException) return error;
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    if (text.isEmpty) {
      return AppException.unknown('An unexpected error occurred.');
    }
    return AppException.unknown(text);
  }

  @override
  String toString() => message;
}
