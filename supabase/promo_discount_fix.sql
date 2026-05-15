-- ============================================================
-- PAFLY Promo Code Discount Fix Migration
-- Run this in Supabase SQL Editor
-- ============================================================

-- 1. Add discount tracking columns to orders table
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS discount_amount NUMERIC(10, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS promo_code_id UUID REFERENCES public.promo_codes(id) ON DELETE SET NULL;

-- 2. Add RLS policies for clients to insert their own promo usage
DROP POLICY IF EXISTS "Users can insert own promo usage" ON public.promo_code_usage;
CREATE POLICY "Users can insert own promo usage" ON public.promo_code_usage
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- 3. Drop old apply_promo_code_to_order and recreate with correct logic
--    The fix: Store discount in orders.discount_amount and orders.promo_code_id
--    instead of mutating total_price / delivery_fee, so the admin always sees
--    the original amounts PLUS the discount that was applied.
DROP FUNCTION IF EXISTS public.apply_promo_code_to_order(BIGINT, UUID);

CREATE OR REPLACE FUNCTION public.apply_promo_code_to_order(
    p_order_id BIGINT,
    p_promo_code_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_promo public.promo_codes%ROWTYPE;
    v_order public.orders%ROWTYPE;
    v_discount_amount NUMERIC(10,2) := 0;
    v_new_total NUMERIC(10,2);
BEGIN
    -- Verify order belongs to current user
    SELECT * INTO v_order FROM public.orders
    WHERE id = p_order_id AND client_id = auth.uid();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order not found or access denied.';
    END IF;

    -- Prevent applying twice
    IF v_order.promo_code_id IS NOT NULL THEN
        RAISE EXCEPTION 'A promo code has already been applied to this order.';
    END IF;

    -- Verify promo code is valid and active
    SELECT * INTO v_promo FROM public.promo_codes
    WHERE id = p_promo_code_id
      AND is_active = true
      AND (expiry_date IS NULL OR expiry_date > now());

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid or expired promo code.';
    END IF;

    -- Check per-user usage limit
    IF v_promo.max_uses_per_user IS NOT NULL THEN
        IF (SELECT COUNT(*) FROM public.promo_code_usage
            WHERE promo_code_id = p_promo_code_id
              AND user_id = auth.uid()) >= v_promo.max_uses_per_user THEN
            RAISE EXCEPTION 'You have reached the usage limit for this promo code.';
        END IF;
    END IF;

    -- Check total usage limit
    IF v_promo.total_max_uses IS NOT NULL THEN
        IF (SELECT COUNT(*) FROM public.promo_code_usage
            WHERE promo_code_id = p_promo_code_id) >= v_promo.total_max_uses THEN
            -- Auto-deactivate if limit was already hit but flag wasn't set
            UPDATE public.promo_codes SET is_active = false WHERE id = p_promo_code_id;
            RAISE EXCEPTION 'This promo code has reached its total usage limit.';
        END IF;
    END IF;

    -- NEW: Check minimum purchase amount (Item Subtotal)
    IF v_promo.min_purchase_amount IS NOT NULL AND v_promo.min_purchase_amount > 0 THEN
        -- Items subtotal = total_price - delivery_fee
        IF (v_order.total_price - v_order.delivery_fee) < v_promo.min_purchase_amount THEN
            RAISE EXCEPTION 'Minimum purchase of % Frw required to use this code.', v_promo.min_purchase_amount;
        END IF;
    END IF;

    -- Compute the product subtotal (total_price - delivery_fee)
    -- Then calculate discount based on type
    IF v_promo.type = 'free_delivery' THEN
        v_discount_amount := v_order.delivery_fee;
    ELSIF v_promo.type = 'discount_fixed' THEN
        v_discount_amount := LEAST(v_promo.value, v_order.total_price);
    ELSIF v_promo.type = 'discount_percent' THEN
        -- Apply percentage only to product subtotal (not delivery)
        v_discount_amount := ROUND(
            (v_order.total_price - v_order.delivery_fee) * (v_promo.value / 100.0),
            2
        );
    END IF;

    -- New total = original total - discount (minimum 0)
    v_new_total := GREATEST(v_order.total_price - v_discount_amount, 0);

    -- Update the order: store discount, promo link, and new total
    -- delivery_fee remains unchanged so admin sees the original fee
    UPDATE public.orders
    SET
        total_price = v_new_total,
        discount_amount = v_discount_amount,
        promo_code_id = p_promo_code_id
    WHERE id = p_order_id;

    -- Record the promo code usage
    INSERT INTO public.promo_code_usage (user_id, promo_code_id, order_id)
    VALUES (auth.uid(), p_promo_code_id, p_order_id)
    ON CONFLICT DO NOTHING;

    -- NEW: Auto-deactivate if total limit is reached
    IF v_promo.total_max_uses IS NOT NULL THEN
        IF (SELECT COUNT(*) FROM public.promo_code_usage
            WHERE promo_code_id = p_promo_code_id) >= v_promo.total_max_uses THEN
            UPDATE public.promo_codes SET is_active = false WHERE id = p_promo_code_id;
        END IF;
    END IF;

    -- Return details for the client app
    RETURN jsonb_build_object(
        'success', true,
        'discount_amount', v_discount_amount,
        'new_total', v_new_total,
        'promo_type', v_promo.type,
        'promo_code', v_promo.code
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.apply_promo_code_to_order(BIGINT, UUID) TO authenticated;

-- 4. Admin discount analytics view
CREATE OR REPLACE VIEW public.admin_discount_report AS
SELECT
    o.id AS order_id,
    o.created_at,
    o.customer_name,
    o.phone,
    pc.code AS promo_code,
    pc.type AS promo_type,
    o.discount_amount,
    o.delivery_fee AS original_delivery_fee,
    (o.total_price + o.discount_amount) AS original_total,
    o.total_price AS final_total,
    o.status
FROM public.orders o
JOIN public.promo_codes pc ON pc.id = o.promo_code_id
WHERE o.promo_code_id IS NOT NULL
ORDER BY o.created_at DESC;

GRANT SELECT ON public.admin_discount_report TO authenticated;
