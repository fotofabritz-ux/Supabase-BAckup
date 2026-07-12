


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






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






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

SET default_tablespace = '';

SET default_table_access_method = "heap";


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
    "reg_gesellschafter" "text"
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


CREATE TABLE IF NOT EXISTS "public"."global_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "start_date" "date" NOT NULL,
    "end_date" "date" NOT NULL,
    "location" "text" NOT NULL,
    "organizer" "text",
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."global_events" OWNER TO "postgres";


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
    "XXX_pl_plz_alt" "text",
    "va_ort" "text",
    "int_check" "text",
    "pl_location" "text",
    "kal_plzort" "text",
    "kal_region" "text" NOT NULL,
    "XXX_pl_id" "text",
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
    "va_land" "text"
);


ALTER TABLE "public"."platzdaten" OWNER TO "postgres";


COMMENT ON TABLE "public"."platzdaten" IS 'Tabelle für Kirmespätze';



COMMENT ON COLUMN "public"."platzdaten"."pl_beschreibung" IS 'Beschreibung des Platzes';



COMMENT ON COLUMN "public"."platzdaten"."va_web" IS 'Veranstalter Webseite';



COMMENT ON COLUMN "public"."platzdaten"."pl_bez" IS 'Bezeichnung des Platzes';



COMMENT ON COLUMN "public"."platzdaten"."XXX_pl_plz_alt" IS 'Alte Postleitzahl mit "D-"';



COMMENT ON COLUMN "public"."platzdaten"."kal_region" IS 'Kalender-Region';



COMMENT ON COLUMN "public"."platzdaten"."futur_start" IS 'Zukünftige Termine Start';



COMMENT ON COLUMN "public"."platzdaten"."pl_plz" IS 'Neue Postleitzahl, rein nummerisch';



COMMENT ON COLUMN "public"."platzdaten"."pl_dauer" IS 'Laufzeit des Platzes';



COMMENT ON COLUMN "public"."platzdaten"."va_land" IS 'Veranstalter, Land';



ALTER TABLE "public"."platzdaten" ALTER COLUMN "nr" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."platzdaten_NR_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."platzdaten_staging" (
    "NR" bigint,
    "pl_bez" "text",
    "pl_ort" "text",
    "pl_plz" "text",
    "kal_region" "text"
);


ALTER TABLE "public"."platzdaten_staging" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "uid" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "role" "text" DEFAULT 'user'::"text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "profiles_role_check" CHECK (("role" = ANY (ARRAY['user'::"text", 'admin'::"text"])))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


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


ALTER TABLE ONLY "public"."bewerbungen"
    ADD CONSTRAINT "bewerbungen_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."firmendaten"
    ADD CONSTRAINT "firmendaten_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."geschaefte"
    ADD CONSTRAINT "geschaefte_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."global_events"
    ADD CONSTRAINT "global_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."help_texts"
    ADD CONSTRAINT "help_texts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."platzdaten"
    ADD CONSTRAINT "platzdaten_pkey" PRIMARY KEY ("nr");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("uid");



ALTER TABLE ONLY "public"."user_events"
    ADD CONSTRAINT "user_events_pkey" PRIMARY KEY ("id");



CREATE UNIQUE INDEX "Platzdaten_NR_unique_idx" ON "public"."platzdaten" USING "btree" ("nr");



CREATE INDEX "bewerbungen_geschaeft_id_idx" ON "public"."bewerbungen" USING "btree" ("geschaeft_id");



CREATE INDEX "bewerbungen_platz_id_idx" ON "public"."bewerbungen" USING "btree" ("platz_id");



CREATE INDEX "bewerbungen_status_idx" ON "public"."bewerbungen" USING "btree" ("status");



CREATE INDEX "bewerbungen_user_id_idx" ON "public"."bewerbungen" USING "btree" ("user_id");



CREATE OR REPLACE TRIGGER "bewerbungen_set_updated_at" BEFORE UPDATE ON "public"."bewerbungen" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "handle_updated_at" BEFORE UPDATE ON "public"."platzdaten" FOR EACH ROW EXECUTE FUNCTION "extensions"."moddatetime"('int_update');



CREATE OR REPLACE TRIGGER "set_profiles_updated_at" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."handle_profiles_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."geschaefte" FOR EACH ROW EXECUTE FUNCTION "public"."handle_updated_at"();



CREATE OR REPLACE TRIGGER "trg_set_kal_region_from_plz" BEFORE INSERT OR UPDATE OF "pl_plz" ON "public"."platzdaten" FOR EACH ROW EXECUTE FUNCTION "public"."set_kal_region_from_plz"();



ALTER TABLE ONLY "public"."bewerbungen"
    ADD CONSTRAINT "bewerbungen_geschaeft_id_fkey" FOREIGN KEY ("geschaeft_id") REFERENCES "public"."geschaefte"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bewerbungen"
    ADD CONSTRAINT "bewerbungen_platz_id_fkey" FOREIGN KEY ("platz_id") REFERENCES "public"."platzdaten"("nr") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bewerbungen"
    ADD CONSTRAINT "bewerbungen_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."firmendaten"
    ADD CONSTRAINT "firmendaten_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."geschaefte"
    ADD CONSTRAINT "geschaefte_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



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



CREATE POLICY "Allow authenticated users to insert/update help texts" ON "public"."help_texts" TO "authenticated" USING (true);



CREATE POLICY "Allow authenticated users to read help texts" ON "public"."help_texts" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can insert global events" ON "public"."global_events" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Authenticated users can view global events" ON "public"."global_events" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."platzdaten" FOR SELECT USING (true);



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



ALTER TABLE "public"."bewerbungen" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."firmendaten" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."geschaefte" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."global_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."help_texts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."platzdaten" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."platzdaten_staging" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_events" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."firmendaten";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."geschaefte";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."global_events";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."user_events";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";





























































































































































































GRANT ALL ON FUNCTION "public"."fill_city_mutator"() TO "anon";
GRANT ALL ON FUNCTION "public"."fill_city_mutator"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fill_city_mutator"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_profiles_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_profiles_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_profiles_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "anon";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_kal_region_from_plz"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_kal_region_from_plz"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_kal_region_from_plz"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";
























GRANT ALL ON TABLE "public"."bewerbungen" TO "anon";
GRANT ALL ON TABLE "public"."bewerbungen" TO "authenticated";
GRANT ALL ON TABLE "public"."bewerbungen" TO "service_role";



GRANT ALL ON TABLE "public"."firmendaten" TO "anon";
GRANT ALL ON TABLE "public"."firmendaten" TO "authenticated";
GRANT ALL ON TABLE "public"."firmendaten" TO "service_role";



GRANT ALL ON TABLE "public"."geschaefte" TO "anon";
GRANT ALL ON TABLE "public"."geschaefte" TO "authenticated";
GRANT ALL ON TABLE "public"."geschaefte" TO "service_role";



GRANT ALL ON TABLE "public"."global_events" TO "anon";
GRANT ALL ON TABLE "public"."global_events" TO "authenticated";
GRANT ALL ON TABLE "public"."global_events" TO "service_role";



GRANT ALL ON TABLE "public"."help_texts" TO "anon";
GRANT ALL ON TABLE "public"."help_texts" TO "authenticated";
GRANT ALL ON TABLE "public"."help_texts" TO "service_role";



GRANT ALL ON TABLE "public"."platzdaten" TO "anon";
GRANT ALL ON TABLE "public"."platzdaten" TO "authenticated";
GRANT ALL ON TABLE "public"."platzdaten" TO "service_role";



GRANT ALL ON SEQUENCE "public"."platzdaten_NR_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."platzdaten_NR_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."platzdaten_NR_seq" TO "service_role";



GRANT ALL ON TABLE "public"."platzdaten_staging" TO "anon";
GRANT ALL ON TABLE "public"."platzdaten_staging" TO "authenticated";
GRANT ALL ON TABLE "public"."platzdaten_staging" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



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



































