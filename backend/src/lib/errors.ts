import type { Context } from "hono";
import type { ContentfulStatusCode } from "hono/utils/http-status";
import { ZodError } from "zod";

export class ApiError extends Error {
  constructor(
    public status: ContentfulStatusCode,
    public code: string,
    message: string,
  ) {
    super(message);
  }
}

export const badRequest = (message: string, code = "bad_request") => new ApiError(400, code, message);
export const unauthorized = (message = "Authentication required") => new ApiError(401, "unauthorized", message);
export const forbidden = (message = "Not allowed") => new ApiError(403, "forbidden", message);
export const notFound = (message = "Not found") => new ApiError(404, "not_found", message);
export const conflict = (message: string, code = "conflict") => new ApiError(409, code, message);
export const tooMany = (message = "Too many requests") => new ApiError(429, "rate_limited", message);

export function handleError(err: Error, c: Context) {
  if (err instanceof ApiError) {
    return c.json({ error: { code: err.code, message: err.message } }, err.status);
  }
  if (err instanceof ZodError) {
    const issue = err.issues[0];
    const where = issue?.path.join(".");
    return c.json(
      { error: { code: "validation_error", message: where ? `${where}: ${issue.message}` : issue?.message ?? "Invalid input" } },
      400,
    );
  }
  console.error(err);
  return c.json({ error: { code: "internal", message: "Internal server error" } }, 500);
}
