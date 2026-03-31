export type LoadErrorCode = "missing_file" | "invalid_json" | "invalid_shape" | "read_error";

export type LoadError = {
  code: LoadErrorCode;
  message: string;
};

export type LoadResult<T> =
  | {
      ok: true;
      data: T;
    }
  | {
      ok: false;
      error: LoadError;
    };
