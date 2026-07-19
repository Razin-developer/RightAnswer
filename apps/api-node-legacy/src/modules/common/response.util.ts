export function ok<T>(data: T, meta: Record<string, unknown> = {}) {
  return {
    success: true,
    data,
    error: null,
    meta,
  };
}

export function fail(code: string, message: string) {
  return {
    success: false,
    data: null,
    error: {
      code,
      message,
    },
    meta: {},
  };
}
