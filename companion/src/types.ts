/** Shared Result type used across all parser modules. */
export type Result<T, E = Error> =
  | { ok: true; value: T }
  | { ok: false; error: E };
