-- Seed data for local/dev testing.
-- Password hashes are bcrypt cost 12.

BEGIN;

-- 1) Plans
INSERT INTO plans (
  name,
  display_name,
  max_concurrent_sessions,
  max_community_members,
  max_communities,
  unattended_access,
  session_recording,
  priority_support,
  custom_alias,
  price_monthly_usd,
  price_yearly_usd
)
VALUES
  ('free', 'Free', 1, 10, 1, FALSE, FALSE, FALSE, FALSE, 0.00, 0.00),
  ('pro', 'Pro', 3, 100, 5, TRUE, TRUE, FALSE, TRUE, 12.00, 120.00),
  ('team', 'Team', 10, 1000, 20, TRUE, TRUE, TRUE, TRUE, 29.00, 290.00),
  ('enterprise', 'Enterprise', NULL, NULL, NULL, TRUE, TRUE, TRUE, TRUE, 99.00, 990.00)
ON CONFLICT (name) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  max_concurrent_sessions = EXCLUDED.max_concurrent_sessions,
  max_community_members = EXCLUDED.max_community_members,
  max_communities = EXCLUDED.max_communities,
  unattended_access = EXCLUDED.unattended_access,
  session_recording = EXCLUDED.session_recording,
  priority_support = EXCLUDED.priority_support,
  custom_alias = EXCLUDED.custom_alias,
  price_monthly_usd = EXCLUDED.price_monthly_usd,
  price_yearly_usd = EXCLUDED.price_yearly_usd;

-- 2) Test users
INSERT INTO users (
  username,
  email,
  password_hash,
  device_id,
  is_verified,
  is_online,
  is_superadmin,
  display_name,
  theme,
  language,
  timezone
)
VALUES
  (
    'admin',
    'admin@bim.com',
    '$2a$12$E1GacQe2wO7tKKESoHud/OX.1gWC8hYHQ9C0n3Kpdej/vPNFb1vWS',
    'seed-admin-device',
    TRUE,
    FALSE,
    TRUE,
    'Admin User',
    'dark',
    'en',
    'UTC'
  ),
  (
    'testuser',
    'user@bim.com',
    '$2a$12$cYVtrFkUJEPexnCg2pl87OweJgmTgcdRiaiHZsw8W6kaI6XWpsQIy',
    'seed-user-device',
    TRUE,
    FALSE,
    FALSE,
    'Test User',
    'dark',
    'en',
    'UTC'
  )
ON CONFLICT (email) DO UPDATE SET
  username = EXCLUDED.username,
  password_hash = EXCLUDED.password_hash,
  device_id = EXCLUDED.device_id,
  is_verified = EXCLUDED.is_verified,
  is_superadmin = EXCLUDED.is_superadmin,
  display_name = EXCLUDED.display_name,
  theme = EXCLUDED.theme,
  language = EXCLUDED.language,
  timezone = EXCLUDED.timezone,
  updated_at = NOW();

-- 3) Test community and 4) admin membership as owner
WITH admin_user AS (
  SELECT id
  FROM users
  WHERE email = 'admin@bim.com'
  LIMIT 1
), upsert_community AS (
  INSERT INTO communities (
    code,
    name,
    description,
    country,
    owner_id,
    is_public
  )
  SELECT
    'BIMHQ',
    'BimStreaming HQ',
    'Seeded default community for local testing',
    'Global',
    admin_user.id,
    TRUE
  FROM admin_user
  ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    country = EXCLUDED.country,
    owner_id = EXCLUDED.owner_id,
    is_public = EXCLUDED.is_public,
    deleted_at = NULL,
    updated_at = NOW()
  RETURNING id, owner_id
)
INSERT INTO community_members (
  community_id,
  user_id,
  role,
  status
)
SELECT
  upsert_community.id,
  upsert_community.owner_id,
  'owner',
  'active'
FROM upsert_community
ON CONFLICT (community_id, user_id) DO UPDATE SET
  role = EXCLUDED.role,
  status = EXCLUDED.status,
  deleted_at = NULL,
  updated_at = NOW();

COMMIT;
