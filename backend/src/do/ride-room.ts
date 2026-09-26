import { DurableObject } from "cloudflare:workers";
import type { Env } from "../env";

const MAX_CHAT_HISTORY = 100;
const MAX_CHAT_LENGTH = 500;

export interface DriverLocation {
  lat: number;
  lng: number;
  heading: number | null;
  at: number;
}

export interface ChatMessage {
  id: string;
  from: "rider" | "driver";
  text: string;
  at: number;
}

/** Messages sent to ride participants. */
export type RoomMessage =
  | { type: "hello"; role: "rider" | "driver"; location: DriverLocation | null; chat: ChatMessage[] }
  | { type: "ride_updated"; ride_id: string; status: string }
  | { type: "driver_location"; location: DriverLocation }
  | { type: "chat"; message: ChatMessage }
  | { type: "pong" }
  | { type: "error"; message: string };

const isNum = (x: unknown): x is number => typeof x === "number" && Number.isFinite(x);

/**
 * One instance per ride. Rider and driver hold WebSockets here to get status
 * changes, the driver's live location and chat. Uses the hibernation API so idle
 * rides cost nothing between messages.
 */
export class RideRoom extends DurableObject<Env> {
  async fetch(request: Request) {
    if (request.headers.get("Upgrade") !== "websocket") return new Response("Expected WebSocket", { status: 426 });
    const role = request.headers.get("X-Role") as "rider" | "driver";
    const userId = request.headers.get("X-User-Id")!;
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1], [role, userId]);
    this.send(pair[1], {
      type: "hello",
      role,
      location: (await this.ctx.storage.get<DriverLocation>("location")) ?? null,
      chat: (await this.ctx.storage.get<ChatMessage[]>("chat")) ?? [],
    });
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  async webSocketMessage(ws: WebSocket, raw: string | ArrayBuffer) {
    let msg: Record<string, unknown>;
    try {
      msg = JSON.parse(typeof raw === "string" ? raw : new TextDecoder().decode(raw));
    } catch {
      return this.send(ws, { type: "error", message: "Invalid JSON" });
    }
    const [role] = this.ctx.getTags(ws) as ["rider" | "driver", string];
    switch (msg.type) {
      case "ping":
        return this.send(ws, { type: "pong" });
      case "location":
        if (role !== "driver") return this.send(ws, { type: "error", message: "Only the driver sends location" });
        if (!isNum(msg.lat) || !isNum(msg.lng)) return this.send(ws, { type: "error", message: "lat and lng are required" });
        return this.driverLocation({ lat: msg.lat, lng: msg.lng, heading: isNum(msg.heading) ? msg.heading : null });
      case "chat": {
        const text = typeof msg.text === "string" ? msg.text.trim().slice(0, MAX_CHAT_LENGTH) : "";
        if (!text) return this.send(ws, { type: "error", message: "text is required" });
        const message: ChatMessage = { id: crypto.randomUUID(), from: role, text, at: Date.now() };
        const chat = (await this.ctx.storage.get<ChatMessage[]>("chat")) ?? [];
        chat.push(message);
        await this.ctx.storage.put("chat", chat.slice(-MAX_CHAT_HISTORY));
        return this.broadcast({ type: "chat", message });
      }
      default:
        return this.send(ws, { type: "error", message: "Unknown message type" });
    }
  }

  async webSocketClose(ws: WebSocket, code: number) {
    try {
      ws.close(code === 1005 ? 1000 : code, "closing");
    } catch {
      // Already closed.
    }
  }

  /** Records and broadcasts the driver's position (from this room or the dispatch socket). */
  async driverLocation(loc: { lat: number; lng: number; heading: number | null }) {
    const location: DriverLocation = { ...loc, at: Date.now() };
    await this.ctx.storage.put("location", location);
    this.broadcast({ type: "driver_location", location }, "rider");
  }

  async rideUpdated(rideId: string, status: string) {
    this.broadcast({ type: "ride_updated", ride_id: rideId, status });
    if (["completed", "cancelled", "no_driver"].includes(status)) {
      // Keep chat for the record but stop holding sockets once the ride is over.
      for (const ws of this.ctx.getWebSockets()) ws.close(1000, "ride ended");
      await this.ctx.storage.delete("location");
    }
  }

  private broadcast(msg: RoomMessage, onlyTag?: "rider" | "driver") {
    for (const ws of this.ctx.getWebSockets(onlyTag)) this.send(ws, msg);
  }

  private send(ws: WebSocket, msg: RoomMessage) {
    try {
      ws.send(JSON.stringify(msg));
    } catch {
      // Socket went away; the runtime will call webSocketClose.
    }
  }
}

export function rideRoom(env: Env, rideId: string) {
  return env.RIDE_ROOM.get(env.RIDE_ROOM.idFromName(rideId));
}
