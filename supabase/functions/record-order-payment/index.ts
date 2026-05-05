import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type PaymentPayload = {
  orderId?: number | string;
  paymentAmount?: number | string;
  paymentNote?: string;
};

type PaymentResult = {
  id: number;
  client_id: string | null;
  customer_name: string;
  product_name: string | null;
  total_price: number;
  paid_amount: number;
  remaining_balance: number;
  status: string;
  previous_status: string;
  payment_amount_recorded: number;
  became_completed: boolean;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = (Deno.env.get("CUSTOM_ANON_KEY") || Deno.env.get("SUPABASE_ANON_KEY"))?.trim();
    const supabaseServiceRoleKey = (Deno.env.get("CUSTOM_SERVICE_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"))?.trim();
    const authHeader = req.headers.get("Authorization") ?? "";

    if (!supabaseUrl || !supabaseAnonKey) {
      throw new Error("Missing Supabase environment variables.");
    }

    if (!authHeader.startsWith("Bearer ")) {
      throw new Error("Missing authorization token.");
    }

    const payload = (await req.json()) as PaymentPayload;
    const orderId = Number(payload.orderId ?? 0);
    const paymentAmount = Number(payload.paymentAmount ?? 0);
    const paymentNote = payload.paymentNote?.trim() || null;

    if (!Number.isFinite(orderId) || orderId <= 0) {
      throw new Error("A valid orderId is required.");
    }

    if (!Number.isFinite(paymentAmount) || paymentAmount <= 0) {
      throw new Error("A valid paymentAmount is required.");
    }

    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: {
        headers: {
          Authorization: authHeader,
        },
      },
    });

    const serviceClient = supabaseServiceRoleKey
      ? createClient(supabaseUrl, supabaseServiceRoleKey, {
          global: {
            headers: {
              apikey: supabaseServiceRoleKey,
              Authorization: `Bearer ${supabaseServiceRoleKey}`,
            },
          },
        })
      : null;

    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) {
      throw new Error("You must be signed in to record a payment.");
    }

    const { data, error } = await userClient.rpc("record_order_payment", {
      target_order_id: orderId,
      payment_amount: paymentAmount,
      payment_note: paymentNote,
    });

    if (error) throw error;

    const paymentResult = Array.isArray(data) ? data[0] as PaymentResult | undefined : undefined;
    if (!paymentResult) {
      throw new Error("Payment workflow returned no result.");
    }

    let notifiedClient = false;
    let notificationWarning: string | null = null;

    if (paymentResult.client_id) {
      try {
        if (!supabaseServiceRoleKey) {
          notificationWarning =
            "Client notification skipped because SUPABASE_SERVICE_ROLE_KEY is not set.";
        } else {
          const notifyResponse = await fetch(
            `${supabaseUrl}/functions/v1/notify-client-event`,
            {
              method: "POST",
              headers: {
                Authorization: `Bearer ${supabaseServiceRoleKey}`,
                apikey: supabaseServiceRoleKey || "",
                "Content-Type": "application/json",
              },
              body: JSON.stringify({
                eventType: "payment_received",
                userId: paymentResult.client_id,
                orderId: paymentResult.id,
                orderStatus: paymentResult.status,
                customerName: paymentResult.customer_name,
                productName: paymentResult.product_name,
                totalPrice: paymentResult.total_price,
                paymentAmount: paymentResult.payment_amount_recorded,
              }),
            },
          );

          if (!notifyResponse.ok) {
            notificationWarning = await notifyResponse.text();
          } else {
            notifiedClient = true;
          }
        }
      } catch (error) {
        notificationWarning = error instanceof Error ? error.message : String(error);
      }
    }

    return Response.json(
      {
        payment: paymentResult,
        notifiedClient,
        notificationWarning,
      },
      { headers: corsHeaders },
    );
  } catch (error) {
    const errorMessage =
      (error as any)?.message ||
      (error as any)?.error_description ||
      (typeof error === "string" ? error : JSON.stringify(error));

    return Response.json(
      { error: errorMessage },
      {
        status: 400,
        headers: corsHeaders,
      },
    );
  }
});
