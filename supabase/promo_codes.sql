-- Table for Promo Codes
CREATE TABLE IF NOT EXISTS public.promo_codes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code TEXT UNIQUE NOT NULL,
    description TEXT,
    type TEXT NOT NULL CHECK (type IN ('free_delivery', 'discount_fixed', 'discount_percent', 'free_product')),
    value DECIMAL DEFAULT 0, -- Used for discount_fixed or discount_percent
    free_product_id UUID REFERENCES public.products(id),
    min_purchase_amount DECIMAL DEFAULT 0,
    max_uses_per_user INTEGER DEFAULT 1,
    total_max_uses INTEGER,
    expiry_date TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT true,
    is_visible_to_all BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Table for Promo Code Usage Tracking
CREATE TABLE IF NOT EXISTS public.promo_code_usage (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) NOT NULL,
    promo_code_id UUID REFERENCES public.promo_codes(id) NOT NULL,
    order_id BIGINT REFERENCES public.orders(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- RLS Policies
ALTER TABLE public.promo_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promo_code_usage ENABLE ROW LEVEL SECURITY;

-- Users can see active and visible promo codes
CREATE POLICY "Users can view visible promo codes" ON public.promo_codes
    FOR SELECT USING (is_active = true AND (is_visible_to_all = true OR expiry_date > now()));

-- Admins have full access
CREATE POLICY "Admins have full access to promo_codes" ON public.promo_codes
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

CREATE POLICY "Admins have full access to promo_code_usage" ON public.promo_code_usage
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- Users can see their own usage
CREATE POLICY "Users can view their own promo usage" ON public.promo_code_usage
    FOR SELECT USING (user_id = auth.uid());

-- RPC to apply promo code to an existing order
CREATE OR REPLACE FUNCTION public.apply_promo_code_to_order(
    p_order_id BIGINT,
    p_promo_code_id UUID
) RETURNS void
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
    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND client_id = auth.uid();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order not found or access denied.';
    END IF;

    -- Verify promo code
    SELECT * INTO v_promo FROM public.promo_codes 
    WHERE id = p_promo_code_id AND is_active = true 
    AND (expiry_date IS NULL OR expiry_date > now());
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid or expired promo code.';
    END IF;

    -- Check max uses per user
    IF v_promo.max_uses_per_user IS NOT NULL THEN
        IF (SELECT count(*) FROM public.promo_code_usage WHERE promo_code_id = p_promo_code_id AND user_id = auth.uid()) >= v_promo.max_uses_per_user THEN
            RAISE EXCEPTION 'Promo code usage limit reached.';
        END IF;
    END IF;

    -- Check total max uses
    IF v_promo.total_max_uses IS NOT NULL THEN
        IF (SELECT count(*) FROM public.promo_code_usage WHERE promo_code_id = p_promo_code_id) >= v_promo.total_max_uses THEN
            RAISE EXCEPTION 'Promo code total usage limit reached.';
        END IF;
    END IF;

    -- Calculate discount
    IF v_promo.type = 'free_delivery' THEN
        v_discount_amount := v_order.delivery_fee;
        UPDATE public.orders SET delivery_fee = 0 WHERE id = p_order_id;
    ELSIF v_promo.type = 'discount_fixed' THEN
        v_discount_amount := v_promo.value;
    ELSIF v_promo.type = 'discount_percent' THEN
        v_discount_amount := (v_order.total_price - v_order.delivery_fee) * (v_promo.value / 100.0);
    END IF;

    v_new_total := GREATEST(v_order.total_price - v_discount_amount, 0);

    UPDATE public.orders 
    SET total_price = v_new_total
    WHERE id = p_order_id;

    INSERT INTO public.promo_code_usage (user_id, promo_code_id, order_id)
    VALUES (auth.uid(), p_promo_code_id, p_order_id);
END;
$$;
