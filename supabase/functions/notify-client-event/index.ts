import { createClient } from "jsr:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type NotifyPayload = {
  eventType?: string;
  userId?: string;
  orderId?: number | string;
  orderStatus?: string;
  customerName?: string;
  productName?: string;
  totalPrice?: number | string;
  paymentAmount?: number | string;
  productId?: string;
  oldPrice?: number | string;
  newPrice?: number | string;
  unit?: string;
};

type ClientTokenRow = {
  fcm_token: string;
  user_id: string;
};

type NotificationTarget = {
  title: string;
  body: string;
  data: Record<string, string>;
  tokens: ClientTokenRow[];
};

type EventType = "order_status" | "payment_received" | "price_update";

const CHANNEL_ID = "fresh_market_updates";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceRoleKey = (Deno.env.get("CUSTOM_SERVICE_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"))?.trim();
    const fcmProjectId = Deno.env.get("FCM_PROJECT_ID")?.trim();
    const fcmClientEmail = Deno.env.get("FCM_CLIENT_EMAIL")?.trim();
    const fcmPrivateKey = Deno.env.get("FCM_PRIVATE_KEY")?.replace(/\\n/g, "\n").replace(/\r/g, "");

    if (!supabaseUrl || !supabaseServiceRoleKey) {
      throw new Error("Missing Supabase service credentials.");
    }

    if (!fcmProjectId || !fcmClientEmail || !fcmPrivateKey) {
      throw new Error("Missing Firebase Messaging environment variables.");
    }

    const payload = (await req.json()) as NotifyPayload;
    const eventType = normalizeEventType(payload.eventType);
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceRoleKey);

    const target = await buildTarget(supabaseAdmin, payload, eventType);
    if (target.tokens.length === 0) {
      return Response.json(
        { sent: 0, failed: 0, message: "No client device tokens registered." },
        { headers: corsHeaders },
      );
    }

    const auth = new GoogleAuth({
      credentials: {
        client_email: fcmClientEmail,
        private_key: fcmPrivateKey,
      },
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });

    const accessToken = await auth.getAccessToken();
    if (!accessToken) {
      throw new Error("Unable to obtain Firebase access token.");
    }

    const sendResults = await Promise.all(
      target.tokens.map(async (tokenRow) => {
        const response = await fetch(
          `https://fcm.googleapis.com/v1/projects/${fcmProjectId}/messages:send`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${accessToken}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              message: {
                token: tokenRow.fcm_token,
                notification: {
                  title: target.title,
                  body: target.body,
                },
                android: {
                  priority: "HIGH",
                  notification: {
                    channel_id: CHANNEL_ID,
                    sound: "default",
                  },
                },
                apns: {
                  payload: {
                    aps: {
                      sound: "default",
                    },
                  },
                },
                data: target.data,
              },
            }),
          },
        );

        const responseBody = await response.text();
        const invalidToken = isInvalidTokenResponse(response.status, responseBody);

        if (invalidToken) {
          await supabaseAdmin
            .from("client_tokens")
            .delete()
            .eq("fcm_token", tokenRow.fcm_token);
        }

        return {
          token: tokenRow.fcm_token,
          ok: response.ok,
          status: response.status,
          body: responseBody,
          invalidToken,
        };
      }),
    );

    return Response.json(
      {
        sent: sendResults.filter((item) => item.ok).length,
        failed: sendResults.filter((item) => !item.ok).length,
        results: sendResults,
      },
      { headers: corsHeaders },
    );
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : String(error) },
      {
        status: 400,
        headers: corsHeaders,
      },
    );
  }
});

function normalizeEventType(value: string | undefined): EventType {
  if (value === "order_status" || value === "payment_received" || value === "price_update") {
    return value;
  }

  throw new Error("Invalid or missing eventType.");
}

async function buildTarget(
  supabaseAdmin: ReturnType<typeof createClient>,
  payload: NotifyPayload,
  eventType: EventType,
): Promise<NotificationTarget> {
  if (eventType === "price_update") {
    const { data, error } = await supabaseAdmin
      .from("client_tokens")
      .select("fcm_token,user_id");

    if (error) throw error;

    return {
      ...buildPriceUpdateMessage(payload),
      tokens: (data ?? []) as ClientTokenRow[],
    };
  }

  const targetUserId = await resolveTargetUserId(supabaseAdmin, payload);
  if (!targetUserId) {
    throw new Error("Missing target userId for client notification.");
  }

  const { data, error } = await supabaseAdmin
    .from("client_tokens")
    .select("fcm_token,user_id")
    .eq("user_id", targetUserId);

  if (error) throw error;

  return {
    ...buildOrderMessage(payload, eventType),
    tokens: (data ?? []) as ClientTokenRow[],
  };
}

async function resolveTargetUserId(
  supabaseAdmin: ReturnType<typeof createClient>,
  payload: NotifyPayload,
): Promise<string | null> {
  const userId = payload.userId?.trim();
  if (userId) return userId;

  const orderId = toNumber(payload.orderId);
  if (!orderId) return null;

  const { data, error } = await supabaseAdmin
    .from("orders")
    .select("client_id")
    .eq("id", orderId)
    .maybeSingle();

  if (error) throw error;

  return data?.client_id ? String(data.client_id) : null;
}

function buildOrderMessage(
  payload: NotifyPayload,
  eventType: Extract<EventType, "order_status" | "payment_received">,
): Omit<NotificationTarget, "tokens"> {
  const orderId = toNumber(payload.orderId);
  const customerName = trimOrFallback(payload.customerName, "");
  const orderLabel = orderId > 0 ? `Order #${orderId}` : "Your order";
  const productName = trimOrFallback(payload.productName, "order");
  const status = trimOrFallback(payload.orderStatus, "updated");

  if (eventType === "order_status") {
    return {
      title: status.toLowerCase() === "completed" ? "🛒 Order Fully Paid" : "🛒 Fresh Market Update",
      body: `Thanks for shopping in Fresh Market!\n\n` + (status.toLowerCase() === "completed"
        ? `${orderLabel} is now fully paid and completed.`
        : `${orderLabel} is now ${status}.`),
      data: {
        eventType,
        orderId: String(orderId || ""),
        orderStatus: status,
        customerName,
        productName,
        totalPrice: String(toNumber(payload.totalPrice)),
      },
    };
  }

  const paymentAmount = toNumber(payload.paymentAmount);
  const fullyPaid = status.toLowerCase() === "completed";
  return {
    title: fullyPaid ? "🛒 Order Fully Paid" : "💵 Payment Received",
    body: `Thanks for shopping in Fresh Market!\n\n` + (fullyPaid
      ? paymentAmount > 0
        ? `${formatCurrency(paymentAmount)} Frw was received for ${orderLabel}. Your order is now fully paid.`
        : `${orderLabel} is now fully paid.`
      : paymentAmount > 0
        ? `${formatCurrency(paymentAmount)} Frw was received for ${orderLabel}.`
        : `A payment was received for ${orderLabel}.`),
    data: {
      eventType,
      orderId: String(orderId || ""),
      orderStatus: status,
      customerName,
      productName,
      totalPrice: String(toNumber(payload.totalPrice)),
      paymentAmount: String(paymentAmount),
    },
  };
}

function buildPriceUpdateMessage(payload: NotifyPayload): Omit<NotificationTarget, "tokens"> {
  const productName = trimOrFallback(payload.productName, "Product");
  const unit = trimOrFallback(payload.unit, "kg");
  const oldPrice = toNumber(payload.oldPrice);
  const newPrice = toNumber(payload.newPrice);
  const oldPart = oldPrice > 0 ? `${formatCurrency(oldPrice)} Frw` : "";
  const newPart = newPrice > 0 ? `${formatCurrency(newPrice)} Frw` : "";

  return {
    title: "Product price updated",
    body: oldPart && newPart
      ? `${productName} changed from ${oldPart} to ${newPart} per ${unit}.`
      : `${productName} now has a new price per ${unit}.`,
    data: {
      eventType: "price_update",
      productId: trimOrFallback(payload.productId, ""),
      productName,
      unit,
      oldPrice: String(oldPrice),
      newPrice: String(newPrice),
    },
  };
}

function trimOrFallback(value: string | undefined, fallback: string): string {
  const trimmed = value?.trim();
  return trimmed && trimmed.length > 0 ? trimmed : fallback;
}

function toNumber(value: number | string | undefined): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function formatCurrency(value: number): string {
  return Math.round(value).toLocaleString("en-US");
}

function isInvalidTokenResponse(status: number, body: string): boolean {
  return status === 404 || status === 410 || body.includes("UNREGISTERED") || body.includes("not registered");
}
