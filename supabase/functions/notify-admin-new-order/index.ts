import { createClient } from "jsr:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type NotifyPayload = {
  eventType?: string;
  orderId?: number;
  customerName?: string;
  paymentMethod?: string;
  totalPrice?: number;
  paymentAmount?: number;
  cancelReason?: string;
  orderDetails?: string;
};

type AdminTokenRow = {
  fcm_token: string;
  user_id: string;
};

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
    const orderId = payload.orderId ?? 0;
    const customerName = payload.customerName?.trim() || "Client";
    const paymentMethod = payload.paymentMethod?.trim() || "Cash";
    const totalPrice = Number(payload.totalPrice ?? 0);
    const paymentAmount = Number(payload.paymentAmount ?? 0);
    const cancelReason = payload.cancelReason?.trim() || "";

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceRoleKey);

    const { data: adminUsers, error: adminUsersError } = await supabaseAdmin
      .from("users")
      .select("id")
      .eq("role", "admin");

    if (adminUsersError) throw adminUsersError;

    const { data: orderRow } = orderId > 0
      ? await supabaseAdmin
        .from("orders")
        .select("shops(owner_id)")
        .eq("id", orderId)
        .maybeSingle()
      : { data: null };

    const shopOwnerId = (orderRow?.shops as { owner_id?: string | null } | null)
      ?.owner_id;

    const adminIds = (adminUsers ?? [])
      .map((row) => row.id as string | null | undefined)
      .filter((id): id is string => Boolean(id));
    if (shopOwnerId && !adminIds.includes(shopOwnerId)) {
      adminIds.push(shopOwnerId);
    }

    if (adminIds.length === 0) {
      return Response.json(
        { sent: 0, message: "No admin users found." },
        { headers: corsHeaders },
      );
    }

    const { data: tokenRows, error: tokenError } = await supabaseAdmin
      .from("admin_tokens")
      .select("fcm_token,user_id")
      .in("user_id", adminIds);

    if (tokenError) throw tokenError;

    const tokens = ((tokenRows ?? []) as AdminTokenRow[])
      .filter((row) => Boolean(row.fcm_token) && row.fcm_token.length > 10);

    if (tokens.length === 0) {
      return Response.json(
        { sent: 0, message: "No admin device tokens registered." },
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

    const title = eventType === "order_cancelled"
      ? "Order cancelled by client"
      : eventType === "payment_received"
        ? "💵 Payment Received"
        : "🛒 New Customer Order";
    const body = eventType === "order_cancelled"
      ? cancelReason
        ? `${customerName} cancelled order #${orderId}: ${truncate(cancelReason, 120)}`
        : `${customerName} cancelled order #${orderId}.`
      : eventType === "payment_received"
        ? `${customerName} paid ${paymentAmount.toFixed(0)} Frw for order #${orderId} via ${paymentMethod}.`
        : `${customerName} placed order #${orderId} • ${paymentMethod} • ${totalPrice.toFixed(0)} Frw
Items: ${payload.orderDetails || "Various items"}`;

    const sendResults = await Promise.all(
      tokens.map(async (tokenRow) => {
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
                  title,
                  body,
                },
                android: {
                  priority: "HIGH",
                  notification: {
                    channel_id: "fresh_market_orders",
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
                data: {
                  title,
                  body,
                  eventType,
                  orderId: `${orderId}`,
                  customerName,
                  paymentMethod,
                  totalPrice: `${totalPrice}`,
                  paymentAmount: `${paymentAmount}`,
                  cancelReason,
                  orderDetails: payload.orderDetails || "",
                },
              },
            }),
          },
        );

        const responseBody = await response.text();
        const invalidToken = isInvalidTokenResponse(response.status, responseBody);

        if (invalidToken) {
          await supabaseAdmin
            .from("admin_tokens")
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

function normalizeEventType(value: string | undefined): "new_order" | "order_cancelled" | "payment_received" {
  if (value === "order_cancelled" || value === "payment_received") {
    return value;
  }
  return "new_order";
}

function truncate(value: string, maxLength: number): string {
  if (value.length <= maxLength) {
    return value;
  }
  return `${value.slice(0, Math.max(0, maxLength - 3))}...`;
}

function isInvalidTokenResponse(status: number, body: string): boolean {
  return status === 404 || status === 410 || body.includes("UNREGISTERED") || body.includes("not registered");
}
