import { describe, expect, it } from "vitest";
import { api, login } from "./helpers";

describe("auth", () => {
  it("normalizes Bangladeshi numbers and logs in with the OTP", async () => {
    const req = await api("POST", "/v1/auth/otp/request", { body: { phone: "01711-000001" } });
    expect(req.status).toBe(200);
    expect(req.body.phone).toBe("+8801711000001");
    expect(req.body.dev_code).toMatch(/^\d{6}$/);

    const res = await api("POST", "/v1/auth/otp/verify", { body: { phone: "+8801711000001", code: req.body.dev_code } });
    expect(res.status).toBe(200);
    expect(res.body.is_new_user).toBe(true);
    expect(res.body.user.phone).toBe("+8801711000001");
    expect(res.body.access_token).toBeTypeOf("string");

    // The code is single-use.
    const again = await api("POST", "/v1/auth/otp/verify", { body: { phone: "+8801711000001", code: req.body.dev_code } });
    expect(again.body.error.code).toBe("otp_expired");
  });

  it("returns the same user on a second login", async () => {
    const first = await login("+8801711000002");
    const second = await login("+8801711000002");
    expect(second.user.id).toBe(first.user.id);
  });

  it("rejects invalid phone numbers", async () => {
    const res = await api("POST", "/v1/auth/otp/request", { body: { phone: "0123456789" } });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe("invalid_phone");
  });

  it("locks the code after too many wrong attempts", async () => {
    const phone = "+8801711000003";
    const req = await api("POST", "/v1/auth/otp/request", { body: { phone } });
    const wrong = req.body.dev_code === "000000" ? "111111" : "000000";
    for (let i = 0; i < 5; i++) {
      const res = await api("POST", "/v1/auth/otp/verify", { body: { phone, code: wrong } });
      expect(res.body.error.code).toBe("otp_invalid");
    }
    const res = await api("POST", "/v1/auth/otp/verify", { body: { phone, code: req.body.dev_code } });
    expect(res.body.error.code).toBe("otp_expired");
  });

  it("rate limits code requests", async () => {
    const phone = "+8801711000004";
    for (let i = 0; i < 5; i++) {
      expect((await api("POST", "/v1/auth/otp/request", { body: { phone } })).status).toBe(200);
    }
    expect((await api("POST", "/v1/auth/otp/request", { body: { phone } })).status).toBe(429);
  });

  it("refreshes tokens and rejects access tokens used as refresh tokens", async () => {
    const { token, refresh } = await login();
    const ok = await api("POST", "/v1/auth/refresh", { body: { refresh_token: refresh } });
    expect(ok.status).toBe(200);
    expect(ok.body.access_token).toBeTypeOf("string");
    const bad = await api("POST", "/v1/auth/refresh", { body: { refresh_token: token } });
    expect(bad.status).toBe(401);
  });

  it("requires a token for protected routes", async () => {
    expect((await api("GET", "/v1/me")).status).toBe(401);
    expect((await api("GET", "/v1/me", { token: "garbage" })).status).toBe(401);
  });
});
