import { exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { api, login } from "./helpers";

describe("profile", () => {
  it("reads and updates the current user", async () => {
    const { token } = await login();
    const me = await api("GET", "/v1/me", { token });
    expect(me.body.user.name).toBeNull();

    const upd = await api("PATCH", "/v1/me", { token, body: { name: "Rahim", email: "rahim@example.com" } });
    expect(upd.status).toBe(200);
    expect(upd.body.user).toMatchObject({ name: "Rahim", email: "rahim@example.com" });

    const cleared = await api("PATCH", "/v1/me", { token, body: { email: null } });
    expect(cleared.body.user).toMatchObject({ name: "Rahim", email: null });

    const invalid = await api("PATCH", "/v1/me", { token, body: { email: "not-an-email" } });
    expect(invalid.status).toBe(400);
  });

  it("uploads and serves an avatar", async () => {
    const { token, user } = await login();
    const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47]);
    const res = await exports.default.fetch("https://api.cholo.test/v1/me/avatar", {
      method: "PUT",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "image/png" },
      body: png,
    });
    expect(res.status).toBe(200);
    const body = await res.json<any>();
    expect(body.user.avatar_url).toBe(`/v1/users/${user.id}/avatar`);

    const img = await exports.default.fetch(`https://api.cholo.test/v1/users/${user.id}/avatar`);
    expect(img.headers.get("Content-Type")).toBe("image/png");
    expect(new Uint8Array(await img.arrayBuffer())).toEqual(png);
  });
});

describe("saved places", () => {
  it("creates, lists and deletes places scoped to the user", async () => {
    const a = await login();
    const b = await login();
    const created = await api("POST", "/v1/me/places", {
      token: a.token,
      body: { label: "Home", address: "Road 11, Banani, Dhaka", lat: 23.7937, lng: 90.4066 },
    });
    expect(created.status).toBe(201);

    expect((await api("GET", "/v1/me/places", { token: a.token })).body.places).toHaveLength(1);
    expect((await api("GET", "/v1/me/places", { token: b.token })).body.places).toHaveLength(0);

    const id = created.body.place.id;
    expect((await api("DELETE", `/v1/me/places/${id}`, { token: b.token })).status).toBe(404);
    expect((await api("DELETE", `/v1/me/places/${id}`, { token: a.token })).status).toBe(204);
  });
});
