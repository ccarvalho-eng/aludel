defmodule Aludel.Repo.Migrations.PreventProviderCredentialPersistence do
  use Ecto.Migration

  def up do
    execute("""
    CREATE FUNCTION aludel_provider_config_credential_key(key_name text)
    RETURNS boolean
    LANGUAGE sql
    IMMUTABLE
    PARALLEL SAFE
    AS $function$
      SELECT
        canonical = ANY (ARRAY['auth', 'bearer', 'key']::text[]) OR
        canonical ~ '(apikey|apisecret|authorization|credential|passwd|password|privatekey|secret)' OR
        canonical ~ '(accesskey|accesskeyid|accountkey|cookie|encryptionkey|sessionkey|signingkey|subscriptionkey|token)$'
      FROM (
        SELECT regexp_replace(lower(btrim(key_name)), '[^a-z0-9]', '', 'g') AS canonical
      ) AS normalized
    $function$;
    """)

    execute("""
    CREATE FUNCTION aludel_provider_config_contains_credentials(config_value jsonb)
    RETURNS boolean
    LANGUAGE plpgsql
    IMMUTABLE
    PARALLEL SAFE
    AS $function$
    DECLARE
      item record;
    BEGIN
      IF config_value IS NULL THEN
        RETURN false;
      END IF;

      IF jsonb_typeof(config_value) = 'object' THEN
        FOR item IN SELECT key, value FROM jsonb_each(config_value)
        LOOP
          IF aludel_provider_config_credential_key(item.key) OR
             aludel_provider_config_contains_credentials(item.value) THEN
            RETURN true;
          END IF;
        END LOOP;
      ELSIF jsonb_typeof(config_value) = 'array' THEN
        FOR item IN SELECT value FROM jsonb_array_elements(config_value)
        LOOP
          IF aludel_provider_config_contains_credentials(item.value) THEN
            RETURN true;
          END IF;
        END LOOP;
      END IF;

      RETURN false;
    END;
    $function$;
    """)

    execute("""
    CREATE FUNCTION aludel_scrub_provider_config_credentials(config_value jsonb)
    RETURNS jsonb
    LANGUAGE plpgsql
    IMMUTABLE
    PARALLEL SAFE
    AS $function$
    DECLARE
      sanitized jsonb;
    BEGIN
      IF config_value IS NULL THEN
        RETURN NULL;
      END IF;

      IF jsonb_typeof(config_value) = 'object' THEN
        SELECT COALESCE(
          jsonb_object_agg(
            entry.key,
            aludel_scrub_provider_config_credentials(entry.value)
          ),
          '{}'::jsonb
        )
        INTO sanitized
        FROM jsonb_each(config_value) AS entry
        WHERE NOT aludel_provider_config_credential_key(entry.key);

        RETURN sanitized;
      ELSIF jsonb_typeof(config_value) = 'array' THEN
        SELECT COALESCE(
          jsonb_agg(
            aludel_scrub_provider_config_credentials(entry.value)
            ORDER BY entry.position
          ),
          '[]'::jsonb
        )
        INTO sanitized
        FROM jsonb_array_elements(config_value) WITH ORDINALITY AS entry(value, position);

        RETURN sanitized;
      END IF;

      RETURN config_value;
    END;
    $function$;
    """)

    execute("""
    UPDATE providers
    SET config = aludel_scrub_provider_config_credentials(config)
    WHERE aludel_provider_config_contains_credentials(config)
    """)

    execute("DROP FUNCTION aludel_scrub_provider_config_credentials(jsonb)")

    create constraint(:providers, :providers_config_no_credentials,
             check: "NOT aludel_provider_config_contains_credentials(config)"
           )
  end

  def down do
    drop constraint(:providers, :providers_config_no_credentials)

    execute("DROP FUNCTION aludel_provider_config_contains_credentials(jsonb)")
    execute("DROP FUNCTION aludel_provider_config_credential_key(text)")
  end
end
