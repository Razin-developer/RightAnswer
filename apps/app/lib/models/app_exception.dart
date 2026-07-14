enum AppErrorType {
  configuration,
  network,
  authentication,
  rateLimit,
  service,
  validation,
  unknown,
}

class AppException implements Exception {
  final AppErrorType type;
  final String title;
  final String message;

  const AppException({
    required this.type,
    required this.title,
    required this.message,
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
