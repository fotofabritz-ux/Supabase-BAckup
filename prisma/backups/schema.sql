


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "hypopg" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "index_advisor" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "moddatetime" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pg_trgm" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."check_valid_token_rate_limit"("p_scope" "text", "p_token" "uuid", "p_max_requests" integer, "p_window_seconds" integer) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  v_now timestamptz := pg_catalog.now();
  v_window interval := pg_catalog.make_interval(secs => p_window_seconds);
  v_bucket text := 'tok:' || p_scope || ':' || p_token::text;
  v_count integer := 0;
BEGIN
  IF pg_catalog.random() < 0.05 THEN
    DELETE FROM public.token_rate_limits
     WHERE window_started_at < (v_now - interval '24 hours');
  END IF;

  INSERT INTO public.token_rate_limits (bucket_key, request_count, window_started_at)
  VALUES (v_bucket, 1, v_now)
  ON CONFLICT (bucket_key) DO UPDATE
    SET request_count = CASE
          WHEN public.token_rate_limits.window_started_at + v_window <= v_now THEN 1
          ELSE public.token_rate_limits.request_count + 1
        END,
        window_started_at = CASE
          WHEN public.token_rate_limits.window_started_at + v_window <= v_now THEN v_now
          ELSE public.token_rate_limits.window_started_at
        END
  RETURNING request_count INTO v_count;

  RETURN v_count <= p_max_requests;
END;
$$;


ALTER FUNCTION "public"."check_valid_token_rate_limit"("p_scope" "text", "p_token" "uuid", "p_max_requests" integer, "p_window_seconds" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fill_city_mutator"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Korrekte Abfrage inklusive FROM-Klausel, um Stadt aus der PLZ-Tabelle zu befüllen
  IF NEW.pl_ort IS NULL AND NEW.pl_plz IS NOT NULL THEN
    SELECT ort INTO NEW.pl_ort 
    FROM plz_daten 
    WHERE plz_daten.plz = NEW.pl_plz 
    LIMIT 1;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fill_city_mutator"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_record_by_token"("p_token" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  v_record public.platzdaten%ROWTYPE;
BEGIN
  IF p_token IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'valid', false,
      'status', 'invalid',
      'message', 'Es wurde kein gültiger Prüf-Token übergeben.'
    );
  END IF;

  SELECT *
    INTO v_record
    FROM public.platzdaten
   WHERE edit_token = p_token
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'valid', false,
      'status', 'invalid',
      'message', 'Dieser Prüf-Link ist ungültig oder existiert nicht.'
    );
  END IF;

  IF v_record.token_expires_at IS NULL OR v_record.token_expires_at <= pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object(
      'valid', false,
      'status', 'expired',
      'message', 'Dieser Prüf-Link ist abgelaufen oder wurde bereits verwendet.'
    );
  END IF;

  IF NOT public.check_valid_token_rate_limit('get', p_token, 15, 60) THEN
    RETURN pg_catalog.jsonb_build_object(
      'valid', false,
      'status', 'rate_limited',
      'message', 'Zu viele Abrufe für diesen Link in kurzer Zeit. Bitte warten Sie einen Moment.'
    );
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'valid', true,
    'status', 'ok',
    'data', pg_catalog.jsonb_build_object(
      'edit_token', v_record.edit_token,
      'token_expires_at', v_record.token_expires_at,
      'pl_bez', COALESCE(v_record.pl_bez, ''),
      'pl_plz', COALESCE(v_record.pl_plz, ''),
      'pl_ort', COALESCE(v_record.pl_ort, ''),
      'pl_start', v_record.pl_start::text,
      'pl_ende', v_record.pl_ende::text,
      'futur_start', v_record.futur_start::text,
      'futur_ende', v_record.futur_ende::text,
      'futur_frist', v_record.futur_frist::text,
      'pl_web', COALESCE(v_record.pl_web, ''),
      'va_name', COALESCE(v_record.va_name, ''),
      'va_adresse', COALESCE(v_record.va_adresse, ''),
      'va_ort', COALESCE(v_record.va_ort, ''),
      'va_web', COALESCE(v_record.va_web, ''),
      'va_email', COALESCE(v_record.va_email, ''),
      'org_on_bew', v_record.org_on_bew,
      'org_on_typ', COALESCE(v_record.org_on_typ, ARRAY[]::text[])
    )
  );
END;
$$;


ALTER FUNCTION "public"."get_record_by_token"("p_token" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  insert into public.profiles (uid, email, role, subscription_status, is_vip)
  values (
    new.id,
    coalesce(nullif(pg_catalog.btrim(new.email), ''), new.id::text || '@no-email.local'),
    'user',
    'inactive',
    false
  )
  on conflict (uid) do nothing;
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_profiles_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_profiles_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."parse_strict_date"("p_raw" "text", "p_field_name" "text") RETURNS "date"
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$
DECLARE
  v_trimmed text := NULLIF(pg_catalog.btrim(COALESCE(p_raw, '')), '');
  v_parts text[];
  v_iso text;
  v_parsed date;
BEGIN
  IF v_trimmed IS NULL THEN
    RETURN NULL;
  END IF;

  IF v_trimmed ~ '^\d{4}-\d{2}-\d{2}$' THEN
    BEGIN
      v_parsed := v_trimmed::date;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'Ungültiges Kalenderdatum für %: %', p_field_name, v_trimmed;
    END;

    IF pg_catalog.to_char(v_parsed, 'YYYY-MM-DD') <> v_trimmed THEN
      RAISE EXCEPTION 'Ungültiges Kalenderdatum für %: %', p_field_name, v_trimmed;
    END IF;

    RETURN v_parsed;
  ELSIF v_trimmed ~ '^\d{1,2}\.\d{1,2}\.\d{4}$' THEN
    v_parts := pg_catalog.string_to_array(v_trimmed, '.');
    v_iso := pg_catalog.format(
      '%s-%s-%s',
      v_parts[3],
      pg_catalog.lpad(v_parts[2], 2, '0'),
      pg_catalog.lpad(v_parts[1], 2, '0')
    );

    BEGIN
      v_parsed := v_iso::date;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'Ungültiges Kalenderdatum für %: %', p_field_name, v_trimmed;
    END;

    IF pg_catalog.to_char(v_parsed, 'YYYY-MM-DD') <> v_iso THEN
      RAISE EXCEPTION 'Ungültiges Kalenderdatum für %: %', p_field_name, v_trimmed;
    END IF;

    RETURN v_parsed;
  END IF;

  RAISE EXCEPTION 'Ungültiges Datumsformat für %: %', p_field_name, v_trimmed;
END;
$_$;


ALTER FUNCTION "public"."parse_strict_date"("p_raw" "text", "p_field_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_platzdaten_history_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RAISE EXCEPTION 'Einträge in public.platzdaten_history sind append-only (UPDATE, DELETE und TRUNCATE sind nicht zulässig).';
END;
$$;


ALTER FUNCTION "public"."prevent_platzdaten_history_mutation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."protect_profile_billing_fields"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  jwt_role text := coalesce(
    nullif(pg_catalog.current_setting('request.jwt.claim.role', true), ''),
    ''
  );
begin
  if jwt_role in ('anon', 'authenticated') then
    if tg_op = 'INSERT' then
      new.role := 'user';
      new.subscription_status := 'inactive';
      new.is_vip := false;
      new.stripe_customer_id := null;
      new.stripe_subscription_id := null;
    elsif tg_op = 'UPDATE' then
      if new.role is distinct from old.role
         or new.is_vip is distinct from old.is_vip
         or new.subscription_status is distinct from old.subscription_status
         or new.stripe_customer_id is distinct from old.stripe_customer_id
         or new.stripe_subscription_id is distinct from old.stripe_subscription_id then
        raise exception 'Unberechtigte Änderung von Rollen-, Abo- oder VIP-Feldern'
          using errcode = '42501';
      end if;
    end if;
  end if;

  new.updated_at := pg_catalog.now();
  return new;
end;
$$;


ALTER FUNCTION "public"."protect_profile_billing_fields"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_kal_region_from_plz"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
declare
  p1 text;
  p2 text;
begin
  -- Falls PLZ fehlt: Standardwert
  if NEW.pl_plz is null then
    NEW.kal_region := 'Ausland';
    return NEW;
  end if;

  p1 := left(NEW.pl_plz::text, 1);
  p2 := left(NEW.pl_plz::text, 2);

  NEW.kal_region :=
    case
      when p1 in ('0','1') then 'O'
      when p2 in ('23','29') then 'O'
      when p2 in ('26','27','28') then 'W'
      when p2 in ('20','21','22','24','25','27') then 'M'
      when p1 in ('4','5','6') then 'W'
      when p2 in ('30','31','38','39') then 'O'
      when p2 in ('32','33','34','35') then 'W'
      when p2 in ('36','37') then 'M'
      when p1 in ('7','8') then 'S'
      when p2 in ('90','91','92','93','94') then 'S'
      when p2 in ('95','96','98','99') then 'O'
      when p2 = '97' then 'M'
      else 'Ausland'
    end;

  return NEW;
end;
$$;


ALTER FUNCTION "public"."set_kal_region_from_plz"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_record_by_token"("p_token" "uuid", "p_data" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  v_pre_expires_at timestamptz;
  v_old_record public.platzdaten%ROWTYPE;
  v_new_record public.platzdaten%ROWTYPE;
  v_payload jsonb := p_data;
  v_invalid_typ text;

  v_pl_bez text;
  v_pl_plz text;
  v_pl_ort text;
  v_pl_start date;
  v_pl_ende date;
  v_futur_start date;
  v_futur_ende date;
  v_futur_frist date;
  v_pl_web text;
  v_va_name text;
  v_va_adresse text;
  v_va_ort text;
  v_va_web text;
  v_va_email text;
  v_org_on_bew boolean;
  v_org_on_typ text[];

  v_has_changes boolean := false;
  v_verified_at timestamptz := pg_catalog.now();
BEGIN
  IF p_token IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'status', 'invalid',
      'message', 'Es wurde kein gültiger Prüf-Token übergeben.'
    );
  END IF;

  IF v_payload IS NULL OR pg_catalog.jsonb_typeof(v_payload) <> 'object' THEN
    RAISE EXCEPTION 'Ungültiger Payload für p_data: JSON-Objekt erwartet, erhalten: %',
      COALESCE(pg_catalog.jsonb_typeof(v_payload), 'null');
  END IF;

  SELECT token_expires_at
    INTO v_pre_expires_at
    FROM public.platzdaten
   WHERE edit_token = p_token
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'status', 'invalid',
      'message', 'Dieser Prüf-Link ist ungültig oder existiert nicht.'
    );
  END IF;

  IF v_pre_expires_at IS NULL OR v_pre_expires_at <= pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'status', 'expired',
      'message', 'Dieser Prüf-Link ist abgelaufen oder wurde bereits verwendet.'
    );
  END IF;

  IF NOT public.check_valid_token_rate_limit('update', p_token, 5, 60) THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'status', 'rate_limited',
      'message', 'Zu viele Speicherversuche für diesen Link. Bitte warten Sie einen Moment.'
    );
  END IF;

  SELECT *
    INTO v_old_record
    FROM public.platzdaten
   WHERE edit_token = p_token
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'status', 'invalid',
      'message', 'Dieser Prüf-Link ist ungültig oder existiert nicht.'
    );
  END IF;

  IF v_old_record.token_expires_at IS NULL OR v_old_record.token_expires_at <= pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'status', 'expired',
      'message', 'Dieser Prüf-Link ist abgelaufen oder wurde bereits verwendet.'
    );
  END IF;

  v_pl_bez := CASE WHEN v_payload ? 'pl_bez' THEN NULLIF(pg_catalog.btrim(COALESCE(v_payload->>'pl_bez', '')), '') ELSE v_old_record.pl_bez END;
  v_pl_plz := CASE WHEN v_payload ? 'pl_plz' THEN NULLIF(pg_catalog.btrim(COALESCE(v_payload->>'pl_plz', '')), '') ELSE v_old_record.pl_plz END;
  v_pl_ort := CASE WHEN v_payload ? 'pl_ort' THEN NULLIF(pg_catalog.btrim(COALESCE(v_payload->>'pl_ort', '')), '') ELSE v_old_record.pl_ort END;
  v_pl_web := CASE WHEN v_payload ? 'pl_web' THEN NULLIF(pg_catalog.btrim(COALESCE(v_payload->>'pl_web', '')), '') ELSE v_old_record.pl_web END;
  v_va_name := CASE WHEN v_payload ? 'va_name' THEN NULLIF(pg_catalog.btrim(COALESCE(v_payload->>'va_name', '')), '') ELSE v_old_record.va_name END;
  v_va_adresse := CASE WHEN v_payload ? 'va_adresse' THEN NULLIF(pg_catalog.btrim(COALESCE(v_payload->>'va_adresse', '')), '') ELSE v_old_record.va_adresse END;
  v_va_ort := CASE WHEN v_payload ? 'va_ort' THEN NULLIF(pg_catalog.btrim(COALESCE(v_payload->>'va_ort', '')), '') ELSE v_old_record.va_ort END;
  v_va_web := CASE WHEN v_payload ? 'va_web' THEN NULLIF(pg_catalog.btrim(COALESCE(v_payload->>'va_web', '')), '') ELSE v_old_record.va_web END;
  v_va_email := CASE WHEN v_payload ? 'va_email' THEN NULLIF(pg_catalog.btrim(COALESCE(v_payload->>'va_email', '')), '') ELSE v_old_record.va_email END;

  v_pl_start := CASE WHEN v_payload ? 'pl_start' THEN public.parse_strict_date(v_payload->>'pl_start', 'pl_start') ELSE v_old_record.pl_start END;
  v_pl_ende := CASE WHEN v_payload ? 'pl_ende' THEN public.parse_strict_date(v_payload->>'pl_ende', 'pl_ende') ELSE v_old_record.pl_ende END;
  v_futur_start := CASE WHEN v_payload ? 'futur_start' THEN public.parse_strict_date(v_payload->>'futur_start', 'futur_start') ELSE v_old_record.futur_start END;
  v_futur_ende := CASE WHEN v_payload ? 'futur_ende' THEN public.parse_strict_date(v_payload->>'futur_ende', 'futur_ende') ELSE v_old_record.futur_ende END;
  v_futur_frist := CASE WHEN v_payload ? 'futur_frist' THEN public.parse_strict_date(v_payload->>'futur_frist', 'futur_frist') ELSE v_old_record.futur_frist END;

  IF v_payload ? 'org_on_bew' THEN
    IF pg_catalog.jsonb_typeof(v_payload->'org_on_bew') = 'null'
       OR NULLIF(pg_catalog.btrim(COALESCE(v_payload->>'org_on_bew', '')), '') IS NULL THEN
      v_org_on_bew := NULL;
    ELSIF pg_catalog.jsonb_typeof(v_payload->'org_on_bew') = 'boolean' THEN
      v_org_on_bew := (v_payload->>'org_on_bew')::boolean;
    ELSIF pg_catalog.lower(v_payload->>'org_on_bew') IN ('true', '1', 'ja') THEN
      v_org_on_bew := true;
    ELSIF pg_catalog.lower(v_payload->>'org_on_bew') IN ('false', '0', 'nein') THEN
      v_org_on_bew := false;
    ELSE
      RAISE EXCEPTION 'Ungültiger Wert für org_on_bew: %', v_payload->>'org_on_bew';
    END IF;
  ELSE
    v_org_on_bew := v_old_record.org_on_bew;
  END IF;

  IF v_payload ? 'org_on_typ' THEN
    IF pg_catalog.jsonb_typeof(v_payload->'org_on_typ') <> 'array' THEN
      RAISE EXCEPTION 'Ungültiger Datentyp für org_on_typ: JSON-Array erwartet, erhalten: %',
        pg_catalog.jsonb_typeof(v_payload->'org_on_typ');
    END IF;

    IF EXISTS (
      SELECT 1
        FROM pg_catalog.jsonb_array_elements(v_payload->'org_on_typ') AS el
       WHERE pg_catalog.jsonb_typeof(el) <> 'string'
    ) THEN
      RAISE EXCEPTION 'Ungültige Elemente in org_on_typ: Nur Zeichenketten erlaubt.';
    END IF;

    SELECT elem
      INTO v_invalid_typ
      FROM pg_catalog.jsonb_array_elements_text(v_payload->'org_on_typ') AS elem
     WHERE NOT (elem = ANY(ARRAY['Webformular', 'PDF', 'Email', 'SQL-Daten', 'Papier-Bewerbung']))
     LIMIT 1;

    IF v_invalid_typ IS NOT NULL THEN
      RAISE EXCEPTION 'Unbekannter oder nicht erlaubter Wert in org_on_typ: %', v_invalid_typ;
    END IF;

    SELECT COALESCE(pg_catalog.array_agg(DISTINCT elem ORDER BY elem), ARRAY[]::text[])
      INTO v_org_on_typ
      FROM pg_catalog.jsonb_array_elements_text(v_payload->'org_on_typ') AS elem;
  ELSE
    SELECT COALESCE(pg_catalog.array_agg(DISTINCT elem ORDER BY elem), ARRAY[]::text[])
      INTO v_org_on_typ
      FROM pg_catalog.unnest(COALESCE(v_old_record.org_on_typ, ARRAY[]::text[])) AS elem;
  END IF;

  v_has_changes := (
    COALESCE(NULLIF(pg_catalog.btrim(v_old_record.pl_bez), ''), '') IS DISTINCT FROM COALESCE(v_pl_bez, '')
    OR COALESCE(NULLIF(pg_catalog.btrim(v_old_record.pl_plz), ''), '') IS DISTINCT FROM COALESCE(v_pl_plz, '')
    OR COALESCE(NULLIF(pg_catalog.btrim(v_old_record.pl_ort), ''), '') IS DISTINCT FROM COALESCE(v_pl_ort, '')
    OR v_old_record.pl_start IS DISTINCT FROM v_pl_start
    OR v_old_record.pl_ende IS DISTINCT FROM v_pl_ende
    OR v_old_record.futur_start IS DISTINCT FROM v_futur_start
    OR v_old_record.futur_ende IS DISTINCT FROM v_futur_ende
    OR v_old_record.futur_frist IS DISTINCT FROM v_futur_frist
    OR COALESCE(NULLIF(pg_catalog.btrim(v_old_record.pl_web), ''), '') IS DISTINCT FROM COALESCE(v_pl_web, '')
    OR COALESCE(NULLIF(pg_catalog.btrim(v_old_record.va_name), ''), '') IS DISTINCT FROM COALESCE(v_va_name, '')
    OR COALESCE(NULLIF(pg_catalog.btrim(v_old_record.va_adresse), ''), '') IS DISTINCT FROM COALESCE(v_va_adresse, '')
    OR COALESCE(NULLIF(pg_catalog.btrim(v_old_record.va_ort), ''), '') IS DISTINCT FROM COALESCE(v_va_ort, '')
    OR COALESCE(NULLIF(pg_catalog.btrim(v_old_record.va_web), ''), '') IS DISTINCT FROM COALESCE(v_va_web, '')
    OR COALESCE(NULLIF(pg_catalog.btrim(v_old_record.va_email), ''), '') IS DISTINCT FROM COALESCE(v_va_email, '')
    OR v_old_record.org_on_bew IS DISTINCT FROM v_org_on_bew
    OR (
      SELECT COALESCE(pg_catalog.array_agg(DISTINCT x ORDER BY x), ARRAY[]::text[])
        FROM pg_catalog.unnest(COALESCE(v_old_record.org_on_typ, ARRAY[]::text[])) AS x
    ) IS DISTINCT FROM COALESCE(v_org_on_typ, ARRAY[]::text[])
  );

  UPDATE public.platzdaten
     SET pl_bez           = v_pl_bez,
         pl_plz           = v_pl_plz,
         pl_ort            = v_pl_ort,
         pl_start          = v_pl_start,
         pl_ende           = v_pl_ende,
         futur_start       = v_futur_start,
         futur_ende        = v_futur_ende,
         futur_frist       = v_futur_frist,
         pl_web            = v_pl_web,
         va_name           = v_va_name,
         va_adresse        = v_va_adresse,
         va_ort            = v_va_ort,
         va_web            = v_va_web,
         va_email          = v_va_email,
         org_on_bew        = v_org_on_bew,
         org_on_typ        = v_org_on_typ,
         verified_at       = v_verified_at,
         token_expires_at  = v_verified_at
   WHERE nr = v_old_record.nr
  RETURNING * INTO v_new_record;

  INSERT INTO public.platzdaten_history (
    record_id,
    old_data,
    new_data,
    changed_at,
    change_source
  ) VALUES (
    v_old_record.nr,
    pg_catalog.to_jsonb(v_old_record),
    pg_catalog.to_jsonb(v_new_record),
    v_verified_at,
    CASE
      WHEN v_has_changes THEN 'self_service_token'
      ELSE 'self_service_verified'
    END
  );

  RETURN pg_catalog.jsonb_build_object(
    'success', true,
    'status', CASE WHEN v_has_changes THEN 'updated' ELSE 'confirmed' END,
    'changed', v_has_changes,
    'verified_at', v_verified_at
  );
END;
$$;


ALTER FUNCTION "public"."update_record_by_token"("p_token" "uuid", "p_data" "jsonb") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."stadtdaten" (
    "pl_ort" "text",
    "nr" bigint NOT NULL,
    "va_adresse" "text",
    "kal_notiz" "text" DEFAULT ''::"text",
    "int_kontrolle" "text",
    "va_email" "text",
    "kal_size" "text",
    "pl_beschreibung" "text",
    "pl_web" "text",
    "va_web" "text",
    "va_name" "text",
    "pl_bez" "text",
    "va_ort" "text",
    "int_check" "text",
    "pl_location" "text",
    "kal_plzort" "text",
    "kal_region" "text" NOT NULL,
    "pl_start" "date",
    "pl_ende" "date",
    "futur_start" "date",
    "futur_ende" "date",
    "futur_frist" "date",
    "int_update" timestamp with time zone DEFAULT "now"(),
    "pl_lat" "text",
    "pl_lon" "text",
    "pl_gplus" "text",
    "pl_attr" "text",
    "pl_plz" "text",
    "pl_dauer" bigint,
    "va_land" "text",
    "org_on_bew" boolean,
    "org_on_name" "text",
    "org_on_url" "text",
    "pl_typ" "text",
    "is_referenced" boolean DEFAULT false,
    "org_on_typ" "text",
    "org_on_intern" "text"
);


ALTER TABLE "public"."stadtdaten" OWNER TO "postgres";


COMMENT ON TABLE "public"."stadtdaten" IS 'Stadtdaten DB für neue Daten';



COMMENT ON COLUMN "public"."stadtdaten"."pl_ort" IS 'Platz, Ort';



COMMENT ON COLUMN "public"."stadtdaten"."va_adresse" IS 'Veranstalter, Strassenname';



COMMENT ON COLUMN "public"."stadtdaten"."int_kontrolle" IS 'Internes Kontrollfeld';



COMMENT ON COLUMN "public"."stadtdaten"."pl_beschreibung" IS 'Beschreibung des Platzes';



COMMENT ON COLUMN "public"."stadtdaten"."pl_web" IS 'Platz, Webseite';



COMMENT ON COLUMN "public"."stadtdaten"."va_web" IS 'Veranstalter Webseite';



COMMENT ON COLUMN "public"."stadtdaten"."va_name" IS 'Veranstalter-Name';



COMMENT ON COLUMN "public"."stadtdaten"."pl_bez" IS 'Bezeichnung des Platzes';



COMMENT ON COLUMN "public"."stadtdaten"."va_ort" IS 'Veranstalter, Ort';



COMMENT ON COLUMN "public"."stadtdaten"."pl_location" IS 'Platz, Lage des Platzes, Ortsbezeichnung';



COMMENT ON COLUMN "public"."stadtdaten"."kal_region" IS 'Kalender-Region';



COMMENT ON COLUMN "public"."stadtdaten"."pl_start" IS 'Platz, Startdatum';



COMMENT ON COLUMN "public"."stadtdaten"."pl_ende" IS 'Platz Enddatum';



COMMENT ON COLUMN "public"."stadtdaten"."futur_start" IS 'Zukünftige Termine Start';



COMMENT ON COLUMN "public"."stadtdaten"."pl_lat" IS 'Platz, Längengrad';



COMMENT ON COLUMN "public"."stadtdaten"."pl_lon" IS 'Platz, Breitengrad';



COMMENT ON COLUMN "public"."stadtdaten"."pl_gplus" IS 'Platz, G+-GeoDaten';



COMMENT ON COLUMN "public"."stadtdaten"."pl_attr" IS 'Platz, Anzahl der Attraktivitäten';



COMMENT ON COLUMN "public"."stadtdaten"."pl_plz" IS 'Neue Postleitzahl, rein nummerisch';



COMMENT ON COLUMN "public"."stadtdaten"."pl_dauer" IS 'Laufzeit des Platzes';



COMMENT ON COLUMN "public"."stadtdaten"."va_land" IS 'Veranstalter, Land';



COMMENT ON COLUMN "public"."stadtdaten"."org_on_bew" IS 'Online-Bewerbung?';



COMMENT ON COLUMN "public"."stadtdaten"."org_on_name" IS 'Begriff, der auf der Webseite gefunden wurde';



ALTER TABLE "public"."stadtdaten" ALTER COLUMN "nr" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."Stadtdaten_nr_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."app_subscriptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "app_code" "text" NOT NULL,
    "stripe_subscription_id" "text" NOT NULL,
    "stripe_price_id" "text" NOT NULL,
    "status" "text" NOT NULL,
    "current_period_start" timestamp with time zone,
    "current_period_end" timestamp with time zone,
    "cancel_at_period_end" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "app_subscriptions_app_code_check" CHECK (("app_code" = ANY (ARRAY['k_tournee_planer'::"text", 'k_radar'::"text", 'wm_finder'::"text"]))),
    CONSTRAINT "app_subscriptions_stripe_price_id_check" CHECK (("btrim"("stripe_price_id") <> ''::"text")),
    CONSTRAINT "app_subscriptions_stripe_subscription_id_check" CHECK (("btrim"("stripe_subscription_id") <> ''::"text"))
);


ALTER TABLE "public"."app_subscriptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."bewerbungen" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "geschaeft_id" "uuid" NOT NULL,
    "platz_id" bigint NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."bewerbungen" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_customers" (
    "user_id" "uuid" NOT NULL,
    "stripe_customer_id" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "billing_customers_stripe_customer_id_check" CHECK (("btrim"("stripe_customer_id") <> ''::"text"))
);


ALTER TABLE "public"."billing_customers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."firmendaten" (
    "user_id" "uuid" NOT NULL,
    "name" "text",
    "inhaber" "text",
    "strasse" "text",
    "plz" "text",
    "ort" "text",
    "telefon" "text",
    "email" "text",
    "webseite" "text",
    "steuernummer" "text",
    "ustid" "text",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "rechtsform" "text",
    "strasse_hausnummer" "text",
    "mobil1" "text",
    "mobil2" "text",
    "whatsapp" "text",
    "ust_id" "text",
    "reg_nummer" "text",
    "reg_ort" "text",
    "fa_ort" "text",
    "rgk_nummer" "text",
    "rgk_ort" "text",
    "rgk_datum" "date",
    "rgk_scan" "text",
    "haftpflicht_gesellschaft" "text",
    "haftpflicht_nummer" "text",
    "haftpflicht_ablauf" "date",
    "haftpflicht_scan" "text",
    "g_bgn" "text",
    "gruendungsdatum" "date",
    "qualifikationen" "text"[] DEFAULT '{}'::"text"[],
    "weitere_angaben" "text",
    "volksfesterfahrung" "text",
    "sachkenntnis_ausbildung" "text",
    "referenzen" "text",
    "ortsansaessigkeit" "text",
    "is_locked" boolean DEFAULT false,
    "steuer_unbedenklichkeit_scan" "text",
    "verbaende" "text"[],
    "lizenzdatum" "date",
    "lizenzstatus" "text",
    "reg_gesellschafter" "text",
    "updates_consent" boolean DEFAULT true,
    "gewerbesteuer" "text",
    "bg_name" "text"
);


ALTER TABLE "public"."firmendaten" OWNER TO "postgres";


COMMENT ON TABLE "public"."firmendaten" IS 'Firmendaten zu KTP';



CREATE TABLE IF NOT EXISTS "public"."geschaefte" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "typ" "text",
    "masse" "text",
    "anschluss" "text",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "sicherheit_text" "text",
    "oekologie_text" "text",
    "barrierefreiheit_text" "text",
    "weitere_merkmale" "text"[] DEFAULT '{}'::"text"[],
    "weitere_merkmale_text" "text",
    "hinweise_verwaltung" "text",
    "notizen_selbst" "text",
    "abruestzeit_tage" integer DEFAULT 0,
    "ruestzeit_tage" integer DEFAULT 0,
    "fuhrpark_details" "jsonb" DEFAULT '[]'::"jsonb",
    "bewerber_eigenschaft" "text",
    "abwasser" boolean DEFAULT false,
    "wasser" boolean DEFAULT false,
    "front" numeric DEFAULT 0,
    "tiefe" numeric DEFAULT 0,
    "hoehe" numeric DEFAULT 0,
    "durchmesser" numeric DEFAULT 0,
    "strom_kw" numeric DEFAULT 0,
    "strom_a" numeric DEFAULT 0,
    "sicherheit_zustand" "text"[],
    "strom_anschluss" "text"[],
    "oekologie_nachhaltigkeit" "text"[],
    "wetter_massnahmen" "text"[],
    "barrierefreiheit" "text"[],
    "fotos_docs" "text"[],
    "zusatz_fotos" "text"[],
    "baubuch_info" "text",
    "baujahr" "text",
    "letzte_renovierung" "text",
    "mindestalter_unbegleitet" integer DEFAULT 0,
    "mindestalter_begleitet" integer DEFAULT 0,
    "mindestgroesse" integer DEFAULT 0,
    "zeichnung" "text",
    "color" "text" DEFAULT '#5A5A40'::"text",
    "sortiment" "text",
    "baubuch_nr" "text",
    "tuev_faelligkeit" "text",
    "ausfuehrungsgenehmigung" "text",
    "preisgestaltung" "text",
    "fuhrpark_keine_fahrzeuge" boolean DEFAULT false,
    "fuhrpark_separate_liste" boolean DEFAULT false
);


ALTER TABLE "public"."geschaefte" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."help_texts" (
    "id" bigint NOT NULL,
    "content" "text" NOT NULL,
    "title" "text",
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."help_texts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."platzdaten" (
    "pl_ort" "text",
    "nr" bigint NOT NULL,
    "va_adresse" "text",
    "kal_notiz" "text" DEFAULT ''::"text",
    "int_kontrolle" "text",
    "va_email" "text",
    "kal_size" "text",
    "pl_beschreibung" "text",
    "pl_web" "text",
    "va_web" "text",
    "va_name" "text",
    "pl_bez" "text",
    "va_ort" "text",
    "int_check" "text",
    "pl_location" "text",
    "kal_plzort" "text",
    "kal_region" "text" NOT NULL,
    "pl_start" "date",
    "pl_ende" "date",
    "futur_start" "date",
    "futur_ende" "date",
    "futur_frist" "date",
    "int_update" timestamp with time zone,
    "pl_lat" "text",
    "pl_lon" "text",
    "pl_gplus" "text",
    "pl_attr" "text",
    "pl_plz" "text",
    "pl_dauer" bigint,
    "va_land" "text",
    "org_on_bew" boolean,
    "org_on_name" "text",
    "pl_typ" "text",
    "org_on_url" "text",
    "is_referenced" boolean DEFAULT false NOT NULL,
    "org_on_typ" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "org_on_intern" "text",
    "markierung" bigint,
    "edit_token" "uuid" DEFAULT "gen_random_uuid"(),
    "token_expires_at" timestamp with time zone,
    "verified_at" timestamp with time zone,
    CONSTRAINT "platzdaten_org_on_typ_check" CHECK (("org_on_typ" <@ ARRAY['PDF'::"text", 'Webformular'::"text", 'SQL-Daten'::"text", 'Papier-Bewerbung'::"text", 'Email'::"text", 'unbek'::"text"]))
);


ALTER TABLE "public"."platzdaten" OWNER TO "postgres";


COMMENT ON TABLE "public"."platzdaten" IS 'Tabelle für Kirmespätze';



COMMENT ON COLUMN "public"."platzdaten"."pl_ort" IS 'Platz, Ort';



COMMENT ON COLUMN "public"."platzdaten"."va_adresse" IS 'Veranstalter, Strassenname';



COMMENT ON COLUMN "public"."platzdaten"."int_kontrolle" IS 'Internes Kontrollfeld';



COMMENT ON COLUMN "public"."platzdaten"."pl_beschreibung" IS 'Beschreibung des Platzes';



COMMENT ON COLUMN "public"."platzdaten"."pl_web" IS 'Platz, Webseite';



COMMENT ON COLUMN "public"."platzdaten"."va_web" IS 'Veranstalter Webseite';



COMMENT ON COLUMN "public"."platzdaten"."va_name" IS 'Veranstalter-Name';



COMMENT ON COLUMN "public"."platzdaten"."pl_bez" IS 'Bezeichnung des Platzes';



COMMENT ON COLUMN "public"."platzdaten"."va_ort" IS 'Veranstalter, Ort';



COMMENT ON COLUMN "public"."platzdaten"."pl_location" IS 'Platz, Lage des Platzes, Ortsbezeichnung';



COMMENT ON COLUMN "public"."platzdaten"."kal_region" IS 'Kalender-Region';



COMMENT ON COLUMN "public"."platzdaten"."pl_start" IS 'Platz, Startdatum';



COMMENT ON COLUMN "public"."platzdaten"."pl_ende" IS 'Platz Enddatum';



COMMENT ON COLUMN "public"."platzdaten"."futur_start" IS 'Zukünftige Termine Start';



COMMENT ON COLUMN "public"."platzdaten"."pl_lat" IS 'Platz, Längengrad';



COMMENT ON COLUMN "public"."platzdaten"."pl_lon" IS 'Platz, Breitengrad';



COMMENT ON COLUMN "public"."platzdaten"."pl_gplus" IS 'Platz, G+-GeoDaten';



COMMENT ON COLUMN "public"."platzdaten"."pl_attr" IS 'Platz, Anzahl der Attraktivitäten';



COMMENT ON COLUMN "public"."platzdaten"."pl_plz" IS 'Neue Postleitzahl, rein nummerisch';



COMMENT ON COLUMN "public"."platzdaten"."pl_dauer" IS 'Laufzeit des Platzes';



COMMENT ON COLUMN "public"."platzdaten"."va_land" IS 'Veranstalter, Land';



COMMENT ON COLUMN "public"."platzdaten"."org_on_bew" IS 'Online-Bewerbung?';



COMMENT ON COLUMN "public"."platzdaten"."org_on_name" IS 'Begriff, der auf der Webseite gefunden wurde';



COMMENT ON COLUMN "public"."platzdaten"."org_on_intern" IS 'Interne Vermerke für Online-Formulare';



ALTER TABLE "public"."platzdaten" ALTER COLUMN "nr" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."platzdaten_NR_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE OR REPLACE VIEW "public"."platzdaten_alphabetisch" WITH ("security_invoker"='true') AS
 SELECT "futur_ende",
    "futur_frist",
    "futur_start",
    "int_check",
    "int_kontrolle",
    "int_update",
    "is_referenced",
    "kal_notiz",
    "kal_plzort",
    "kal_region",
    "kal_size",
    "nr",
    "org_on_bew",
    "org_on_name",
    "org_on_url",
    "pl_attr",
    "pl_bez",
    "pl_beschreibung",
    "pl_dauer",
    "pl_ende",
    "pl_gplus",
    "pl_lat",
    "pl_location",
    "pl_lon",
    "pl_ort",
    "pl_plz",
    "pl_start",
    "pl_typ",
    "pl_web",
    "va_adresse",
    "va_email",
    "va_land",
    "va_name",
    "va_ort",
    "va_web"
   FROM "public"."platzdaten";


ALTER VIEW "public"."platzdaten_alphabetisch" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."platzdaten_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "record_id" bigint NOT NULL,
    "old_data" "jsonb" NOT NULL,
    "new_data" "jsonb" NOT NULL,
    "changed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "change_source" "text" DEFAULT 'self_service_token'::"text" NOT NULL
);


ALTER TABLE "public"."platzdaten_history" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."platzdaten_staging" (
    "pl_ort" "text",
    "nr" bigint NOT NULL,
    "va_adresse" "text",
    "kal_notiz" "text" DEFAULT ''::"text",
    "int_kontrolle" "text",
    "va_email" "text",
    "kal_size" "text",
    "pl_beschreibung" "text",
    "pl_web" "text",
    "va_web" "text",
    "va_name" "text",
    "pl_bez" "text",
    "va_ort" "text",
    "int_check" "text",
    "pl_location" "text",
    "kal_plzort" "text",
    "kal_region" "text" NOT NULL,
    "pl_start" "date",
    "pl_ende" "date",
    "futur_start" "date",
    "futur_ende" "date",
    "futur_frist" "date",
    "int_update" timestamp with time zone,
    "pl_lat" "text",
    "pl_lon" "text",
    "pl_gplus" "text",
    "pl_attr" "text",
    "pl_plz" "text",
    "pl_dauer" bigint,
    "va_land" "text",
    "org_on_bew" boolean,
    "org_on_name" "text",
    "pl_typ" "text",
    "org_on_url" "text",
    "is_referenced" boolean DEFAULT false NOT NULL,
    "org_on_typ" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "org_on_intern" "text",
    "markierung" bigint,
    CONSTRAINT "platzdaten_org_on_typ_check" CHECK (("org_on_typ" <@ ARRAY['PDF'::"text", 'Webformular'::"text", 'SQL-Daten'::"text", 'Papier-Bewerbung'::"text", 'Email'::"text", 'unbek'::"text"]))
);


ALTER TABLE "public"."platzdaten_staging" OWNER TO "postgres";


COMMENT ON COLUMN "public"."platzdaten_staging"."pl_ort" IS 'Platz, Ort';



COMMENT ON COLUMN "public"."platzdaten_staging"."va_adresse" IS 'Veranstalter, Strassenname';



COMMENT ON COLUMN "public"."platzdaten_staging"."int_kontrolle" IS 'Internes Kontrollfeld';



COMMENT ON COLUMN "public"."platzdaten_staging"."pl_beschreibung" IS 'Beschreibung des Platzes';



COMMENT ON COLUMN "public"."platzdaten_staging"."pl_web" IS 'Platz, Webseite';



COMMENT ON COLUMN "public"."platzdaten_staging"."va_web" IS 'Veranstalter Webseite';



COMMENT ON COLUMN "public"."platzdaten_staging"."va_name" IS 'Veranstalter-Name';



COMMENT ON COLUMN "public"."platzdaten_staging"."pl_bez" IS 'Bezeichnung des Platzes';



COMMENT ON COLUMN "public"."platzdaten_staging"."va_ort" IS 'Veranstalter, Ort';



COMMENT ON COLUMN "public"."platzdaten_staging"."pl_location" IS 'Platz, Lage des Platzes, Ortsbezeichnung';



COMMENT ON COLUMN "public"."platzdaten_staging"."kal_region" IS 'Kalender-Region';



COMMENT ON COLUMN "public"."platzdaten_staging"."pl_start" IS 'Platz, Startdatum';



COMMENT ON COLUMN "public"."platzdaten_staging"."pl_ende" IS 'Platz Enddatum';



COMMENT ON COLUMN "public"."platzdaten_staging"."futur_start" IS 'Zukünftige Termine Start';



COMMENT ON COLUMN "public"."platzdaten_staging"."pl_lat" IS 'Platz, Längengrad';



COMMENT ON COLUMN "public"."platzdaten_staging"."pl_lon" IS 'Platz, Breitengrad';



COMMENT ON COLUMN "public"."platzdaten_staging"."pl_gplus" IS 'Platz, G+-GeoDaten';



COMMENT ON COLUMN "public"."platzdaten_staging"."pl_attr" IS 'Platz, Anzahl der Attraktivitäten';



COMMENT ON COLUMN "public"."platzdaten_staging"."pl_plz" IS 'Neue Postleitzahl, rein nummerisch';



COMMENT ON COLUMN "public"."platzdaten_staging"."pl_dauer" IS 'Laufzeit des Platzes';



COMMENT ON COLUMN "public"."platzdaten_staging"."va_land" IS 'Veranstalter, Land';



COMMENT ON COLUMN "public"."platzdaten_staging"."org_on_bew" IS 'Online-Bewerbung?';



COMMENT ON COLUMN "public"."platzdaten_staging"."org_on_name" IS 'Begriff, der auf der Webseite gefunden wurde';



COMMENT ON COLUMN "public"."platzdaten_staging"."org_on_intern" IS 'Interne Vermerke für Online-Formulare';



ALTER TABLE "public"."platzdaten_staging" ALTER COLUMN "nr" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."platzdaten_staging_nr_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "uid" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "role" "text" DEFAULT 'user'::"text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updates_consent" boolean DEFAULT true,
    "subscription_status" "text" DEFAULT 'inactive'::"text" NOT NULL,
    "is_vip" boolean DEFAULT false NOT NULL,
    "stripe_customer_id" "text",
    "stripe_subscription_id" "text",
    CONSTRAINT "profiles_role_check" CHECK (("role" = ANY (ARRAY['user'::"text", 'admin'::"text"])))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."stripe_webhook_events" (
    "stripe_event_id" "text" NOT NULL,
    "event_type" "text" NOT NULL,
    "received_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "processed_at" timestamp with time zone,
    "processing_error" "text",
    CONSTRAINT "stripe_webhook_events_stripe_event_id_check" CHECK (("btrim"("stripe_event_id") <> ''::"text"))
);


ALTER TABLE "public"."stripe_webhook_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."token_rate_limits" (
    "bucket_key" "text" NOT NULL,
    "request_count" integer DEFAULT 1 NOT NULL,
    "window_started_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."token_rate_limits" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "start_date" "date" NOT NULL,
    "end_date" "date" NOT NULL,
    "location" "text",
    "type" "text" DEFAULT 'event'::"text",
    "color" "text" DEFAULT '#5A5A40'::"text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."user_events" OWNER TO "postgres";


ALTER TABLE ONLY "public"."stadtdaten"
    ADD CONSTRAINT "Stadtdaten_pkey" PRIMARY KEY ("nr");



ALTER TABLE ONLY "public"."app_subscriptions"
    ADD CONSTRAINT "app_subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."app_subscriptions"
    ADD CONSTRAINT "app_subscriptions_stripe_subscription_id_key" UNIQUE ("stripe_subscription_id");



ALTER TABLE ONLY "public"."bewerbungen"
    ADD CONSTRAINT "bewerbungen_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_customers"
    ADD CONSTRAINT "billing_customers_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."billing_customers"
    ADD CONSTRAINT "billing_customers_stripe_customer_id_key" UNIQUE ("stripe_customer_id");



ALTER TABLE ONLY "public"."firmendaten"
    ADD CONSTRAINT "firmendaten_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."geschaefte"
    ADD CONSTRAINT "geschaefte_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."help_texts"
    ADD CONSTRAINT "help_texts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."platzdaten"
    ADD CONSTRAINT "platzdaten_edit_token_key" UNIQUE ("edit_token");



ALTER TABLE ONLY "public"."platzdaten_history"
    ADD CONSTRAINT "platzdaten_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."platzdaten"
    ADD CONSTRAINT "platzdaten_pkey" PRIMARY KEY ("nr");



ALTER TABLE ONLY "public"."platzdaten_staging"
    ADD CONSTRAINT "platzdaten_staging_pkey" PRIMARY KEY ("nr");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("uid");



ALTER TABLE ONLY "public"."stripe_webhook_events"
    ADD CONSTRAINT "stripe_webhook_events_pkey" PRIMARY KEY ("stripe_event_id");



ALTER TABLE ONLY "public"."token_rate_limits"
    ADD CONSTRAINT "token_rate_limits_pkey" PRIMARY KEY ("bucket_key");



ALTER TABLE ONLY "public"."user_events"
    ADD CONSTRAINT "user_events_pkey" PRIMARY KEY ("id");



CREATE UNIQUE INDEX "Platzdaten_NR_unique_idx" ON "public"."platzdaten" USING "btree" ("nr");



CREATE UNIQUE INDEX "Stadtdaten_NR_idx" ON "public"."stadtdaten" USING "btree" ("nr");



CREATE INDEX "app_subscriptions_user_app_idx" ON "public"."app_subscriptions" USING "btree" ("user_id", "app_code");



CREATE INDEX "bewerbungen_geschaeft_id_idx" ON "public"."bewerbungen" USING "btree" ("geschaeft_id");



CREATE INDEX "bewerbungen_platz_id_idx" ON "public"."bewerbungen" USING "btree" ("platz_id");



CREATE INDEX "bewerbungen_status_idx" ON "public"."bewerbungen" USING "btree" ("status");



CREATE INDEX "bewerbungen_user_id_idx" ON "public"."bewerbungen" USING "btree" ("user_id");



CREATE INDEX "idx_platzdaten_history_record_id" ON "public"."platzdaten_history" USING "btree" ("record_id", "changed_at" DESC);



CREATE INDEX "idx_platzdaten_unverified_email" ON "public"."platzdaten" USING "btree" ("va_email", "nr") WHERE (("verified_at" IS NULL) AND ("va_email" IS NOT NULL) AND ("btrim"("va_email") <> ''::"text"));



CREATE INDEX "platzdaten_pl_typ_idx" ON "public"."platzdaten" USING "btree" ("pl_typ");



CREATE UNIQUE INDEX "platzdaten_staging_NR_idx" ON "public"."platzdaten_staging" USING "btree" ("nr");



CREATE INDEX "platzdaten_staging_pl_typ_idx" ON "public"."platzdaten_staging" USING "btree" ("pl_typ");



CREATE OR REPLACE TRIGGER "bewerbungen_set_updated_at" BEFORE UPDATE ON "public"."bewerbungen" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "handle_updated_at" BEFORE UPDATE ON "public"."platzdaten" FOR EACH ROW EXECUTE FUNCTION "extensions"."moddatetime"('int_update');



CREATE OR REPLACE TRIGGER "set_profiles_updated_at" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."handle_profiles_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."geschaefte" FOR EACH ROW EXECUTE FUNCTION "public"."handle_updated_at"();



CREATE OR REPLACE TRIGGER "trg_platzdaten_history_append_only" BEFORE DELETE OR UPDATE ON "public"."platzdaten_history" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_platzdaten_history_mutation"();



CREATE OR REPLACE TRIGGER "trg_platzdaten_history_no_truncate" BEFORE TRUNCATE ON "public"."platzdaten_history" FOR EACH STATEMENT EXECUTE FUNCTION "public"."prevent_platzdaten_history_mutation"();



CREATE OR REPLACE TRIGGER "trg_protect_profile_billing_fields" BEFORE INSERT OR UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."protect_profile_billing_fields"();



CREATE OR REPLACE TRIGGER "trg_set_kal_region_from_plz" BEFORE INSERT OR UPDATE OF "pl_plz" ON "public"."platzdaten" FOR EACH ROW EXECUTE FUNCTION "public"."set_kal_region_from_plz"();



ALTER TABLE ONLY "public"."app_subscriptions"
    ADD CONSTRAINT "app_subscriptions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."bewerbungen"
    ADD CONSTRAINT "bewerbungen_geschaeft_id_fkey" FOREIGN KEY ("geschaeft_id") REFERENCES "public"."geschaefte"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bewerbungen"
    ADD CONSTRAINT "bewerbungen_platz_id_fkey" FOREIGN KEY ("platz_id") REFERENCES "public"."platzdaten"("nr") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bewerbungen"
    ADD CONSTRAINT "bewerbungen_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_customers"
    ADD CONSTRAINT "billing_customers_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."firmendaten"
    ADD CONSTRAINT "firmendaten_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."geschaefte"
    ADD CONSTRAINT "geschaefte_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."platzdaten_history"
    ADD CONSTRAINT "platzdaten_history_record_id_fkey" FOREIGN KEY ("record_id") REFERENCES "public"."platzdaten"("nr") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."platzdaten"
    ADD CONSTRAINT "platzdaten_markierung_fkey" FOREIGN KEY ("markierung") REFERENCES "public"."platzdaten"("nr");



ALTER TABLE ONLY "public"."platzdaten_staging"
    ADD CONSTRAINT "platzdaten_staging_markierung_fkey" FOREIGN KEY ("markierung") REFERENCES "public"."platzdaten_staging"("nr");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_uid_fkey" FOREIGN KEY ("uid") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_events"
    ADD CONSTRAINT "user_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Admin platzdaten delete" ON "public"."platzdaten" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."uid" = "auth"."uid"()) AND ("p"."role" = 'admin'::"text")))));



CREATE POLICY "Admin platzdaten insert" ON "public"."platzdaten" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."uid" = "auth"."uid"()) AND ("p"."role" = 'admin'::"text")))));



CREATE POLICY "Admin platzdaten select" ON "public"."platzdaten" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."uid" = "auth"."uid"()) AND ("p"."role" = 'admin'::"text")))));



CREATE POLICY "Admin platzdaten update" ON "public"."platzdaten" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."uid" = "auth"."uid"()) AND ("p"."role" = 'admin'::"text"))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."uid" = "auth"."uid"()) AND ("p"."role" = 'admin'::"text")))));



CREATE POLICY "Allow all for anon" ON "public"."platzdaten" USING (true) WITH CHECK (true);



CREATE POLICY "Allow all for anon on stadtdaten" ON "public"."stadtdaten" TO "authenticated", "anon" USING (true) WITH CHECK (true);



CREATE POLICY "Allow authenticated users to insert/update help texts" ON "public"."help_texts" TO "authenticated" USING (true);



CREATE POLICY "Allow authenticated users to read help texts" ON "public"."help_texts" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."platzdaten" FOR SELECT USING (true);



CREATE POLICY "Nutzer dürfen eigenes Profil lesen" ON "public"."profiles" FOR SELECT TO "authenticated" USING (("uid" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can delete their own businesses" ON "public"."geschaefte" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own events" ON "public"."user_events" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own geschaefte" ON "public"."geschaefte" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert their own businesses" ON "public"."geschaefte" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert their own events" ON "public"."user_events" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert their own firmendaten" ON "public"."firmendaten" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert their own geschaefte" ON "public"."geschaefte" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert their own profile" ON "public"."profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "uid"));



CREATE POLICY "Users can manage own firmendaten" ON "public"."firmendaten" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can manage own geschaefte" ON "public"."geschaefte" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can manage their own bewerbungen" ON "public"."bewerbungen" TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users can update their own businesses" ON "public"."geschaefte" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own events" ON "public"."user_events" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own firmendaten" ON "public"."firmendaten" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own geschaefte" ON "public"."geschaefte" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own profile" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "uid"));



CREATE POLICY "Users can view their own businesses" ON "public"."geschaefte" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own events" ON "public"."user_events" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own firmendaten" ON "public"."firmendaten" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own geschaefte" ON "public"."geschaefte" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own profile" ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "uid"));



ALTER TABLE "public"."app_subscriptions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "app_subscriptions_read_own" ON "public"."app_subscriptions" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."bewerbungen" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."billing_customers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."firmendaten" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."geschaefte" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."help_texts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."platzdaten" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."platzdaten_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."platzdaten_staging" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."stadtdaten" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."stripe_webhook_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."token_rate_limits" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_events" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."firmendaten";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."geschaefte";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."user_events";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";


























































































































































































































































































REVOKE ALL ON FUNCTION "public"."check_valid_token_rate_limit"("p_scope" "text", "p_token" "uuid", "p_max_requests" integer, "p_window_seconds" integer) FROM PUBLIC;



GRANT ALL ON FUNCTION "public"."fill_city_mutator"() TO "anon";
GRANT ALL ON FUNCTION "public"."fill_city_mutator"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fill_city_mutator"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_record_by_token"("p_token" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_record_by_token"("p_token" "uuid") TO "anon";



REVOKE ALL ON FUNCTION "public"."handle_new_user"() FROM PUBLIC;



GRANT ALL ON FUNCTION "public"."handle_profiles_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_profiles_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_profiles_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."parse_strict_date"("p_raw" "text", "p_field_name" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."prevent_platzdaten_history_mutation"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."protect_profile_billing_fields"() FROM PUBLIC;



GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "anon";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_kal_region_from_plz"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_kal_region_from_plz"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_kal_region_from_plz"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_record_by_token"("p_token" "uuid", "p_data" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_record_by_token"("p_token" "uuid", "p_data" "jsonb") TO "anon";
























GRANT ALL ON TABLE "public"."stadtdaten" TO "anon";
GRANT ALL ON TABLE "public"."stadtdaten" TO "authenticated";
GRANT ALL ON TABLE "public"."stadtdaten" TO "service_role";



GRANT ALL ON SEQUENCE "public"."Stadtdaten_nr_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."Stadtdaten_nr_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."Stadtdaten_nr_seq" TO "service_role";



GRANT ALL ON TABLE "public"."app_subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."app_subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."app_subscriptions" TO "service_role";



GRANT ALL ON TABLE "public"."bewerbungen" TO "anon";
GRANT ALL ON TABLE "public"."bewerbungen" TO "authenticated";
GRANT ALL ON TABLE "public"."bewerbungen" TO "service_role";



GRANT ALL ON TABLE "public"."billing_customers" TO "anon";
GRANT ALL ON TABLE "public"."billing_customers" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_customers" TO "service_role";



GRANT ALL ON TABLE "public"."firmendaten" TO "anon";
GRANT ALL ON TABLE "public"."firmendaten" TO "authenticated";
GRANT ALL ON TABLE "public"."firmendaten" TO "service_role";



GRANT ALL ON TABLE "public"."geschaefte" TO "anon";
GRANT ALL ON TABLE "public"."geschaefte" TO "authenticated";
GRANT ALL ON TABLE "public"."geschaefte" TO "service_role";



GRANT ALL ON TABLE "public"."help_texts" TO "anon";
GRANT ALL ON TABLE "public"."help_texts" TO "authenticated";
GRANT ALL ON TABLE "public"."help_texts" TO "service_role";



GRANT ALL ON TABLE "public"."platzdaten" TO "anon";
GRANT ALL ON TABLE "public"."platzdaten" TO "authenticated";
GRANT ALL ON TABLE "public"."platzdaten" TO "service_role";



GRANT ALL ON SEQUENCE "public"."platzdaten_NR_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."platzdaten_NR_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."platzdaten_NR_seq" TO "service_role";



GRANT ALL ON TABLE "public"."platzdaten_alphabetisch" TO "anon";
GRANT ALL ON TABLE "public"."platzdaten_alphabetisch" TO "authenticated";
GRANT ALL ON TABLE "public"."platzdaten_alphabetisch" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."platzdaten_history" TO "service_role";



GRANT ALL ON TABLE "public"."platzdaten_staging" TO "anon";
GRANT ALL ON TABLE "public"."platzdaten_staging" TO "authenticated";
GRANT ALL ON TABLE "public"."platzdaten_staging" TO "service_role";



GRANT ALL ON SEQUENCE "public"."platzdaten_staging_nr_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."platzdaten_staging_nr_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."platzdaten_staging_nr_seq" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."stripe_webhook_events" TO "anon";
GRANT ALL ON TABLE "public"."stripe_webhook_events" TO "authenticated";
GRANT ALL ON TABLE "public"."stripe_webhook_events" TO "service_role";



GRANT ALL ON TABLE "public"."token_rate_limits" TO "service_role";



GRANT ALL ON TABLE "public"."user_events" TO "anon";
GRANT ALL ON TABLE "public"."user_events" TO "authenticated";
GRANT ALL ON TABLE "public"."user_events" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";



































