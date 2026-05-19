-- --- MIGRATION: 20251221105951_9ea8a135-95d9-47c7-9251-0c36781abd1f.sql ---
-- Create profiles table for usernames and avatars
CREATE TABLE public.profiles (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL UNIQUE,
  username TEXT NOT NULL,
  avatar_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Create policies for profiles
CREATE POLICY "Profiles are viewable by everyone" 
ON public.profiles 
FOR SELECT 
USING (true);

CREATE POLICY "Users can update their own profile" 
ON public.profiles 
FOR UPDATE 
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own profile" 
ON public.profiles 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Create live chat messages table
CREATE TABLE public.live_chat_messages (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  channel_id TEXT NOT NULL,
  user_id UUID NOT NULL,
  username TEXT NOT NULL,
  avatar_url TEXT,
  message TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.live_chat_messages ENABLE ROW LEVEL SECURITY;

-- Create policies for live chat messages
CREATE POLICY "Anyone can view chat messages" 
ON public.live_chat_messages 
FOR SELECT 
USING (true);

CREATE POLICY "Authenticated users can insert chat messages" 
ON public.live_chat_messages 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Enable realtime for messages
ALTER PUBLICATION supabase_realtime ADD TABLE public.live_chat_messages;

-- Create function to update timestamps
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- Create trigger for automatic timestamp updates
CREATE TRIGGER update_profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- --- MIGRATION: 20251227140233_bce1b449-d355-4f54-8b6e-702a714b8540.sql ---
-- Create watchlist table
CREATE TABLE public.watchlist (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  content_id INTEGER NOT NULL,
  content_type TEXT NOT NULL CHECK (content_type IN ('movie', 'tv')),
  title TEXT NOT NULL,
  poster_path TEXT,
  vote_average NUMERIC,
  release_date TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id, content_id, content_type)
);

-- Enable Row Level Security
ALTER TABLE public.watchlist ENABLE ROW LEVEL SECURITY;

-- Users can view their own watchlist
CREATE POLICY "Users can view their own watchlist"
ON public.watchlist
FOR SELECT
USING (auth.uid() = user_id);

-- Users can add to their own watchlist
CREATE POLICY "Users can add to their own watchlist"
ON public.watchlist
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Users can remove from their own watchlist
CREATE POLICY "Users can delete from their own watchlist"
ON public.watchlist
FOR DELETE
USING (auth.uid() = user_id);

-- --- MIGRATION: 20260104004643_66f5c572-3d46-479b-b81e-1c5dc4974e81.sql ---
-- Allow users to delete their own chat messages
CREATE POLICY "Users can delete their own messages"
ON public.live_chat_messages
FOR DELETE
USING (auth.uid() = user_id);

-- --- MIGRATION: 20260104014626_d4b96d59-53a8-46e2-8ec1-569881a7d957.sql ---
-- Drop the existing delete policy that only allows users to delete their own messages
DROP POLICY IF EXISTS "Users can delete their own messages" ON public.live_chat_messages;

-- Create new policy that allows any authenticated user to delete any message
CREATE POLICY "Authenticated users can delete any message" 
ON public.live_chat_messages 
FOR DELETE 
USING (auth.uid() IS NOT NULL);

-- --- MIGRATION: 20260104105152_f37d3066-c5f3-4110-b7f6-0f1ac70e77ef.sql ---
-- Create table for site analytics
CREATE TABLE public.site_analytics (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  event_type TEXT NOT NULL DEFAULT 'page_view',
  page_path TEXT NOT NULL,
  content_id TEXT,
  content_type TEXT,
  content_title TEXT,
  visitor_id TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.site_analytics ENABLE ROW LEVEL SECURITY;

-- Allow anyone to insert analytics (anonymous tracking)
CREATE POLICY "Anyone can insert analytics"
ON public.site_analytics
FOR INSERT
WITH CHECK (true);

-- Allow anyone to read aggregated analytics (for display)
CREATE POLICY "Anyone can read analytics"
ON public.site_analytics
FOR SELECT
USING (true);

-- Create index for faster queries
CREATE INDEX idx_analytics_created_at ON public.site_analytics(created_at);
CREATE INDEX idx_analytics_page_path ON public.site_analytics(page_path);
CREATE INDEX idx_analytics_content ON public.site_analytics(content_id, content_type);

-- --- MIGRATION: 20260104110929_c36cdeb4-7c80-4199-9bd1-fde609050b7a.sql ---
-- Create role enum
CREATE TYPE public.app_role AS ENUM ('admin', 'moderator', 'user');

-- Create user_roles table
CREATE TABLE public.user_roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    role app_role NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    UNIQUE (user_id, role)
);

-- Enable RLS
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- Security definer function to check roles (prevents recursive RLS)
CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role app_role)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role = _role
  )
$$;

-- RLS policies for user_roles
CREATE POLICY "Users can view their own roles"
ON public.user_roles
FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all roles"
ON public.user_roles
FOR SELECT
USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can manage roles"
ON public.user_roles
FOR ALL
USING (public.has_role(auth.uid(), 'admin'));

-- --- MIGRATION: 20260121120439_f97869cc-7f1b-4621-8d58-3a27fa3548f8.sql ---
-- Create channels table for Live TV management
CREATE TABLE public.channels (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name text NOT NULL,
  logo_url text,
  stream_url text NOT NULL,
  stream_type text NOT NULL DEFAULT 'hls',
  drm_key_id text,
  drm_key text,
  category text DEFAULT 'general',
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Enable Row Level Security
ALTER TABLE public.channels ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can view active channels
CREATE POLICY "Anyone can view active channels" 
ON public.channels 
FOR SELECT 
USING (is_active = true);

-- Policy: Admins can view all channels (including inactive)
CREATE POLICY "Admins can view all channels" 
ON public.channels 
FOR SELECT 
USING (public.has_role(auth.uid(), 'admin'));

-- Policy: Admins can insert channels
CREATE POLICY "Admins can insert channels" 
ON public.channels 
FOR INSERT 
WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- Policy: Admins can update channels
CREATE POLICY "Admins can update channels" 
ON public.channels 
FOR UPDATE 
USING (public.has_role(auth.uid(), 'admin'));

-- Policy: Admins can delete channels
CREATE POLICY "Admins can delete channels" 
ON public.channels 
FOR DELETE 
USING (public.has_role(auth.uid(), 'admin'));

-- Add trigger for updated_at
CREATE TRIGGER update_channels_updated_at
BEFORE UPDATE ON public.channels
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- --- MIGRATION: 20260123133414_c73cec5e-4350-4b67-b4e7-900018f38ce3.sql ---
-- Create site_settings table for customizable content
CREATE TABLE public.site_settings (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  key text NOT NULL UNIQUE,
  value jsonb NOT NULL DEFAULT '{}',
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.site_settings ENABLE ROW LEVEL SECURITY;

-- Anyone can read settings
CREATE POLICY "Anyone can read site settings"
ON public.site_settings
FOR SELECT
USING (true);

-- Only admins can modify settings
CREATE POLICY "Admins can insert site settings"
ON public.site_settings
FOR INSERT
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can update site settings"
ON public.site_settings
FOR UPDATE
USING (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can delete site settings"
ON public.site_settings
FOR DELETE
USING (has_role(auth.uid(), 'admin'::app_role));

-- Create trigger for updated_at
CREATE TRIGGER update_site_settings_updated_at
BEFORE UPDATE ON public.site_settings
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- Insert default welcome popup settings
INSERT INTO public.site_settings (key, value)
VALUES ('welcome_popup', '{
  "enabled": true,
  "emoji": "🎬",
  "title": "Welcome to TVStreamz!",
  "message": "Stream your favorite movies, TV shows, anime, and live TV channels for free. Enjoy unlimited entertainment anytime, anywhere!",
  "button_text": "Start Watching 🍿",
  "tags": ["Movies", "TV Shows", "Anime", "Live TV"]
}'::jsonb);

-- --- MIGRATION: 20260126013259_a958f882-4266-4ed9-bb57-f40539007e4c.sql ---
-- Insert default PopAds settings
INSERT INTO public.site_settings (key, value)
VALUES ('popads_settings', '{
  "enabled": true,
  "siteId": 4983507,
  "minBid": 0,
  "popundersPerIP": "0",
  "delayBetween": 0,
  "defaultPerDay": 0,
  "topmostLayer": "auto"
}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- --- MIGRATION: 20260201100328_2778e577-05db-427d-8147-7e135a149578.sql ---
-- Add Widevine DRM support columns to channels table
ALTER TABLE public.channels 
ADD COLUMN IF NOT EXISTS license_type text DEFAULT NULL,
ADD COLUMN IF NOT EXISTS license_url text DEFAULT NULL;

-- Add comment for documentation
COMMENT ON COLUMN public.channels.license_type IS 'DRM license type: clearkey, widevine, or null for no DRM';
COMMENT ON COLUMN public.channels.license_url IS 'License server URL for Widevine DRM';

-- --- MIGRATION: 20260202092542_724afced-82bd-434c-b553-8e4f03bdb8b5.sql ---
-- Create a function to get daily analytics stats (aggregated)
CREATE OR REPLACE FUNCTION get_daily_analytics_stats(days_back integer DEFAULT 30)
RETURNS TABLE (
  stat_date date,
  view_count bigint,
  visitor_count bigint
) 
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT 
    DATE(created_at) as stat_date,
    COUNT(*) as view_count,
    COUNT(DISTINCT visitor_id) as visitor_count
  FROM site_analytics
  WHERE created_at >= NOW() - (days_back || ' days')::interval
  GROUP BY DATE(created_at)
  ORDER BY stat_date ASC;
$$;

-- --- MIGRATION: 20260219034519_f93cfcdf-1bf9-436c-bc95-b778659450cc.sql ---
ALTER TABLE public.channels ADD COLUMN user_agent TEXT DEFAULT NULL;

-- --- MIGRATION: 20260219134837_ec2e79ca-4e29-4a0a-9a33-8e725062b211.sql ---
ALTER TABLE public.channels ADD COLUMN use_proxy boolean NOT NULL DEFAULT false;

-- --- MIGRATION: 20260220000404_a4c926a1-2369-4143-a272-8bf3fdec40cd.sql ---
ALTER TABLE public.channels ADD COLUMN referrer text DEFAULT NULL;

-- --- MIGRATION: 20260227233733_fc3e07b6-b4f7-4ee4-8db0-d06018c99500.sql ---
-- Fix overly permissive site_analytics INSERT policy
-- Replace WITH CHECK (true) with basic input validation
DROP POLICY IF EXISTS "Anyone can insert analytics" ON public.site_analytics;

CREATE POLICY "Anyone can insert analytics"
ON public.site_analytics
FOR INSERT
WITH CHECK (
  length(visitor_id) > 0 AND length(visitor_id) <= 100
  AND length(page_path) > 0 AND length(page_path) <= 500
  AND length(event_type) > 0 AND length(event_type) <= 50
  AND (content_id IS NULL OR length(content_id) <= 200)
  AND (content_type IS NULL OR length(content_type) <= 50)
  AND (content_title IS NULL OR length(content_title) <= 500)
);

-- --- MIGRATION: 20260306003724_f6788fb4-6215-47da-9fb7-5ed794f7ae6f.sql ---
ALTER TABLE public.channels ADD COLUMN proxy_order jsonb DEFAULT NULL;

-- --- MIGRATION: 20260309041526_209bc1bb-4334-48d3-b0fb-490680357d7b.sql ---

CREATE TABLE public.tvapp_cache (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  slug text NOT NULL UNIQUE,
  resolved_url text NOT NULL,
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

ALTER TABLE public.tvapp_cache DISABLE ROW LEVEL SECURITY;


-- --- MIGRATION: 20260309052136_9993a654-5353-443f-a49b-dbc984b4a0be.sql ---
UPDATE channels SET use_proxy = true, proxy_order = '["primary","backup","backup2","backup3","backup4"]'::jsonb WHERE id = '3cf4c259-2931-4ee5-92dc-4939099bbf2b';

-- --- MIGRATION: 20260312015623_d1aa741b-7d56-4370-b54f-7b0256b63604.sql ---
UPDATE channels 
SET stream_url = 'https://wmjebiejrjgfafsniqlx.supabase.co/functions/v1/stream-proxy?url=http://trilo.tv/live/Eden1/123456789/368076.m3u8',
    updated_at = now()
WHERE id = '3cf4c259-2931-4ee5-92dc-4939099bbf2b';

-- --- MIGRATION: 20260313101429_8ae13f6c-b024-4270-9c0b-7857654b486c.sql ---

CREATE TABLE public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  message text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read notifications"
  ON public.notifications FOR SELECT
  TO public
  USING (true);

CREATE POLICY "Admins can insert notifications"
  ON public.notifications FOR INSERT
  TO public
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can update notifications"
  ON public.notifications FOR UPDATE
  TO public
  USING (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can delete notifications"
  ON public.notifications FOR DELETE
  TO public
  USING (has_role(auth.uid(), 'admin'::app_role));


-- --- MIGRATION: 20260316000439_0f1b8dfe-0407-449b-aa41-378223c215ee.sql ---
ALTER TABLE public.channels ADD COLUMN IF NOT EXISTS proxy_type text NOT NULL DEFAULT 'none';

-- --- MIGRATION: 20260407105740_add_status_to_channels.sql ---
ALTER TABLE public.channels ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'online';
COMMENT ON COLUMN public.channels.status IS 'Current status of the channel: online or offline';


-- --- MIGRATION: 20260414011800_fix_favorites_persistence.sql ---
-- Fix content_id type to support strings (for channel UUIDs) and update content_type constraint
-- We use DO blocks to safely handle tables that might or might not have these specific constraints

DO $$ 
BEGIN
    -- Update watchlist table if it exists
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'watchlist') THEN
        -- Alter content_id to TEXT
        ALTER TABLE public.watchlist ALTER COLUMN content_id TYPE TEXT;
        
        -- Update content_type constraint
        ALTER TABLE public.watchlist DROP CONSTRAINT IF EXISTS watchlist_content_type_check;
        ALTER TABLE public.watchlist ADD CONSTRAINT watchlist_content_type_check 
            CHECK (content_type IN ('movie', 'tv', 'channel'));
    END IF;

    -- Update user_my_list table if it exists
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_my_list') THEN
        -- Alter content_id to TEXT
        ALTER TABLE public.user_my_list ALTER COLUMN content_id TYPE TEXT;
        
        -- Update content_type constraint
        ALTER TABLE public.user_my_list DROP CONSTRAINT IF EXISTS user_my_list_content_type_check;
        ALTER TABLE public.user_my_list ADD CONSTRAINT user_my_list_content_type_check 
            CHECK (content_type IN ('movie', 'tv', 'channel'));
    END IF;
END $$;


-- --- MIGRATION: 20260512191500_create_missing_sync_tables.sql ---
-- Create community_messages table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.community_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT NOT NULL,
    message TEXT NOT NULL,
    parent_id UUID REFERENCES public.community_messages(id) ON DELETE CASCADE,
    reply_to_username TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Create user_watch_history table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.user_watch_history (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content_id TEXT NOT NULL,
    content_type TEXT NOT NULL CHECK (content_type IN ('movie', 'tv')),
    title TEXT NOT NULL,
    poster_path TEXT,
    backdrop_path TEXT,
    progress NUMERIC DEFAULT 0,
    "current_time" NUMERIC DEFAULT 0,
    duration NUMERIC DEFAULT 0,
    season INTEGER,
    episode INTEGER,
    last_server TEXT,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    PRIMARY KEY (user_id, content_id, content_type)
);

-- Create user_my_list table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.user_my_list (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content_id TEXT NOT NULL,
    content_type TEXT NOT NULL CHECK (content_type IN ('movie', 'tv', 'channel')),
    title TEXT NOT NULL,
    poster_path TEXT,
    vote_average NUMERIC,
    added_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE (user_id, content_id, content_type)
);

-- Create custom_channels table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.custom_channels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    stream_url TEXT NOT NULL,
    logo_url TEXT,
    stream_type TEXT,
    proxy_type TEXT,
    drm_key TEXT,
    drm_key_id TEXT,
    license_type TEXT,
    license_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Create user_preferences table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.user_preferences (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    my_list JSONB DEFAULT '[]'::jsonb,
    watch_history JSONB DEFAULT '[]'::jsonb,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- Create user_requests table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.user_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT,
    email TEXT,
    channel_id TEXT,
    message TEXT NOT NULL,
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable Row Level Security (RLS) on all tables if not already enabled
ALTER TABLE public.community_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_watch_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_my_list ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.custom_channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_requests ENABLE ROW LEVEL SECURITY;

-- Safety blocks to create policies if they don't already exist
DO $$
BEGIN
    -- community_messages policies
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'community_messages' AND policyname = 'Anyone can view community messages') THEN
        CREATE POLICY "Anyone can view community messages" ON public.community_messages FOR SELECT USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'community_messages' AND policyname = 'Authenticated users can insert community messages') THEN
        CREATE POLICY "Authenticated users can insert community messages" ON public.community_messages FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'community_messages' AND policyname = 'Users can delete their own community messages, or admins') THEN
        CREATE POLICY "Users can delete their own community messages, or admins" ON public.community_messages FOR DELETE USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'));
    END IF;

    -- user_watch_history policies
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_watch_history' AND policyname = 'Users can view their own watch history') THEN
        CREATE POLICY "Users can view their own watch history" ON public.user_watch_history FOR SELECT USING (auth.uid() = user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_watch_history' AND policyname = 'Users can insert their own watch history') THEN
        CREATE POLICY "Users can insert their own watch history" ON public.user_watch_history FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_watch_history' AND policyname = 'Users can update their own watch history') THEN
        CREATE POLICY "Users can update their own watch history" ON public.user_watch_history FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_watch_history' AND policyname = 'Users can delete their own watch history') THEN
        CREATE POLICY "Users can delete their own watch history" ON public.user_watch_history FOR DELETE USING (auth.uid() = user_id);
    END IF;

    -- user_my_list policies
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_my_list' AND policyname = 'Users can view their own my_list') THEN
        CREATE POLICY "Users can view their own my_list" ON public.user_my_list FOR SELECT USING (auth.uid() = user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_my_list' AND policyname = 'Users can insert their own my_list') THEN
        CREATE POLICY "Users can insert their own my_list" ON public.user_my_list FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_my_list' AND policyname = 'Users can delete their own my_list') THEN
        CREATE POLICY "Users can delete their own my_list" ON public.user_my_list FOR DELETE USING (auth.uid() = user_id);
    END IF;

    -- custom_channels policies
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'custom_channels' AND policyname = 'Users can view their own custom channels') THEN
        CREATE POLICY "Users can view their own custom channels" ON public.custom_channels FOR SELECT USING (auth.uid() = user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'custom_channels' AND policyname = 'Users can insert their own custom channels') THEN
        CREATE POLICY "Users can insert their own custom channels" ON public.custom_channels FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'custom_channels' AND policyname = 'Users can update their own custom channels') THEN
        CREATE POLICY "Users can update their own custom channels" ON public.custom_channels FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'custom_channels' AND policyname = 'Users can delete their own custom channels') THEN
        CREATE POLICY "Users can delete their own custom channels" ON public.custom_channels FOR DELETE USING (auth.uid() = user_id);
    END IF;

    -- user_preferences policies
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_preferences' AND policyname = 'Users can view their own preferences') THEN
        CREATE POLICY "Users can view their own preferences" ON public.user_preferences FOR SELECT USING (auth.uid() = id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_preferences' AND policyname = 'Users can insert their own preferences') THEN
        CREATE POLICY "Users can insert their own preferences" ON public.user_preferences FOR INSERT WITH CHECK (auth.uid() = id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_preferences' AND policyname = 'Users can update their own preferences') THEN
        CREATE POLICY "Users can update their own preferences" ON public.user_preferences FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
    END IF;

    -- user_requests policies
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_requests' AND policyname = 'Users can view their own requests') THEN
        CREATE POLICY "Users can view their own requests" ON public.user_requests FOR SELECT USING (auth.uid() = user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_requests' AND policyname = 'Admins can view all requests') THEN
        CREATE POLICY "Admins can view all requests" ON public.user_requests FOR SELECT USING (public.has_role(auth.uid(), 'admin'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_requests' AND policyname = 'Authenticated users can insert requests') THEN
        CREATE POLICY "Authenticated users can insert requests" ON public.user_requests FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_requests' AND policyname = 'Admins can delete any requests') THEN
        CREATE POLICY "Admins can delete any requests" ON public.user_requests FOR DELETE USING (public.has_role(auth.uid(), 'admin'));
    END IF;
END $$;

-- Enable Realtime publication for community_messages so chats load instantly without refreshing
alter publication supabase_realtime add table community_messages;


-- --- MIGRATION: 20260513011000_add_epg_columns_to_channels.sql ---
-- Add EPG and channel number columns to public.channels table
ALTER TABLE public.channels ADD COLUMN IF NOT EXISTS epg_id TEXT DEFAULT NULL;
ALTER TABLE public.channels ADD COLUMN IF NOT EXISTS channel_num TEXT DEFAULT NULL;
ALTER TABLE public.channels ADD COLUMN IF NOT EXISTS epg_url TEXT DEFAULT NULL;

-- Add comments for clarity
COMMENT ON COLUMN public.channels.epg_id IS 'EPG ID / Name used to map channel to electronic program guide data';
COMMENT ON COLUMN public.channels.channel_num IS 'Logical channel number displayed in the client UI';
COMMENT ON COLUMN public.channels.epg_url IS 'External XMLTV EPG URL for manual channel listings';


-- -----------------------------------------------------
-- --- INSERT CHANNELS DATA FROM CSV ---
-- -----------------------------------------------------

ALTER TABLE public.channels DISABLE TRIGGER ALL;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('0d224a02-2a73-4357-ac7e-bbedd8ed16f6', '3rsSinePinoy', 'https://i.imgur.com/OCS1l7Gl.jpg', 'https://live20.bozztv.com/giatvplayout7/giatv-210267/tracks-v1a1/mono.ts.m3u8', 'hls', NULL, NULL, 'general', true, 0, '2026-03-17 10:38:39.653543+00', '2026-04-08 02:49:33.70825+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('50607368-904c-4534-bef6-c5fa630f8856', '3rsMovieBoxPh', 'https://i.imgur.com/b4rjf8nl.png', 'https://live20.bozztv.com/giatvplayout7/giatv-210731/tracks-v1a1/mono.ts.m3u8', 'hls', NULL, NULL, 'general', true, 0, '2026-03-17 10:37:53.162626+00', '2026-04-08 02:49:33.700611+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('c1b3c224-4b9a-4364-9119-5a00096b8283', 'Animal Planet', 'https://api.discovery.com/v1/images/5bc91c366b66d1494068339e?aspectRatio=1x1&width=192&key=3020a40c2356a645b4b4', 'https://nog-live1-ott.izzigo.tv/12/out/u/dash/ANIMAL-PLANET-HD/default.mpd', 'mpd', 'ecc518be0092c0ed80d8b1eeb243c5b6', '7292a98762ff0ce0cf7ab33158f95ecf', 'documentary', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:49:42.490846+00', 'clearkey', NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('4e0a417d-b265-48d1-9ff8-6ae3db3ca367', 'KCM', NULL, 'https://amg02159-amg02159c10-amgplt0352.playout.now3.amagi.tv/playlist.m3u8', 'hls', NULL, NULL, 'general', true, 0, '2026-03-20 03:05:14.871993+00', '2026-04-08 02:50:54.722135+00', NULL, NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('60b44d13-4f31-4c18-95a7-d1bb6403b805', 'Animax', 'https://i.imgur.com/VLlyHhT.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_animax_sd_new/default/index.mpd', 'mpd', '92032b0e41a543fb9830751273b8debd', '03f8b65e2af785b10d6634735dbe6c11', 'Anime', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:49:44.596204+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('ef1b7855-4a06-42b0-95bb-a6c7770bab3f', 'GTV', 'https://i.imgur.com/geuq18u.png', 'http://136.239.173.10:6610/001/2/ch00000090990000001143/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20TsXah2%2FZLFNNIdWrVrXDMArwAtJC%2BsmBQ5ARU076BdkhsyK4TH4mOENKJ45mwOyS0g%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001313&contentid=ch00000000000000001313&videoid=ch00000090990000001143&recommendtype=0&userid=1430687738767&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=VTF7PQ0PAOMXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO&IASHttpSessionId=RR20446820260101155238998726&ispcode=55', 'mpd', NULL, NULL, 'general', true, 0, '2026-02-02 13:39:43.960651+00', '2026-04-08 02:50:31.759695+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('2b2cc543-2013-41f3-b629-ab0536f74053', 'Heart Of Asia', 'https://aphrodite.gmanetwork.com/entertainment/articles/900_675_10__20200706111150.jpg', 'https://poohlover.serv00.net/stream-proxy.php?url=http%3A%2F%2Fhls.nathcreqtives.com%2Fplaylist.m3u8%3Fid%3D1%26token%3DeyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJHYW1heXBvdG90b3kiLCJpYXQiOjE3NjkxNjM3MTcsImV4cCI6MTc3MDAyNzcxNywiYWNjb3VudEV4cGlyZWQiOmZhbHNlLCJhY2NvdW50RXhwaXJlc0F0IjoxNzcwMDI3NzE3fQ.K1-8AV1nHuKVEUe8kE0SqLfLrqk1n4Ng0WBkX18zGI4', 'hls', NULL, NULL, 'general', false, 1, '2026-01-26 09:25:36.356519+00', '2026-04-08 02:50:40.29918+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('e92190b5-3647-4fc4-8dc7-4f137d657bc2', 'Nickjr', 'https://vignette.wikia.nocookie.net/logaekranowe/images/4/45/1024px-Nick_Jr._logo_2009.svg.png/revision/latest?cb=20180616122202&path-prefix=pl', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/dr_nickjr/default/index.mpd', 'mpd', 'bab5c11178b646749fbae87962bf5113', '0ac679aad3b9d619ac39ad634ec76bc8', 'kids', true, 0, '2026-02-19 14:03:15.902679+00', '2026-04-08 02:51:07.140718+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('f8b3cea3-e0f6-449c-a616-5df1cb4560e8', 'Anime X Hidive', 'https://www.tablotv.com/wp-content/uploads/2023/12/AnimeXHIDIVE_official-768x499.png', 'https://amc-anime-x-hidive-1-us.tablo.wurl.tv/playlist.m3u8', 'hls', NULL, NULL, 'Anime', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:49:44.862825+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('15f0f8e7-261f-4266-a680-b917c75f09f7', 'Attack on Titan: The Final Season', 'https://wallpapercat.com/w/full/d/f/3/210987-3840x2160-desktop-4k-attack-on-titan-the-final-season-background-image.jpg', 'https://www.youtube.com/embed/lqYnQDCygEM?autoplay=1', 'youtube', NULL, NULL, 'general', false, 0, '2026-02-08 09:31:26.381591+00', '2026-04-08 02:49:49.36271+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('49fa1f3c-8a93-4350-8ca3-3807dc4f284f', 'DepEd Channel', 'https://th.bing.com/th/id/OIP.MPPdJ1ObiLG4Q6MFEDQ4pAHaEH?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/depedch_sd/default/index.mpd', 'mpd', '0f853706412b11edb8780242ac120002', '2157d6529d80a760f60a8b5350dbc4df', 'education', true, 0, '2026-02-19 14:01:30.092577+00', '2026-04-08 02:50:11.989675+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('4cc92e34-67ee-48d0-bbb7-a622f8e3fed8', 'Frieren: Beyond Journey''s End Tagalog Marathon', 'https://cdn.displate.com/artwork/270x380/2025-02-03/7807fbe59ffdd3f11f42d8c08b8cc37d_c1cefa1a087f8988ad74e1733a951d39.jpg', 'https://www.youtube.com/embed/LbgzcZyl-BY?autoplay=1', 'youtube', NULL, NULL, 'general', false, 0, '2026-01-25 13:37:19.889412+00', '2026-04-08 02:50:25.698172+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('fd966c75-633c-47e4-9acb-ec8600e2f69f', 'I Heart Movies', 'https://aphrodite.gmanetwork.com/entertainment/shows/images/1200_675_1349x400__20210329175218.jpg', 'https://hls.nathcreqtives.com/playlist.m3u8?id=2&token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJXZXNsZXkiLCJpYXQiOjE3NzQ2NjYxMDYsImV4cCI6MTgwMjk1ODQwMywiYWNjb3VudEV4cGlyZWQiOmZhbHNlLCJhY2NvdW50RXhwaXJlc0F0IjoxODAyOTU4NDAzLCJhbGxvd2VkT3JpZ2lucyI6WyJodHRwczovL2hvbWUubmF0aGNyZXF0aXZlcy5jb20iXX0.8_9sRDpADeWb82nTw7ydJ6UhqtXxMxGD0n88NWeUxZU', 'hls', NULL, NULL, 'general', false, 0, '2026-01-26 09:17:48.546512+00', '2026-04-08 02:50:44.974134+00', NULL, NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'offline', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('d0508195-ec5a-4e38-9beb-6c914eb0b30e', 'Net25', 'https://i.imgur.com/smr8TGJ.png', 'http://136.239.159.20:6610/001/2/ch00000090990000001090/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20TsXah2%2FZLFNNIdWrVrXDMApBCCDeDIJn9rDuWx8BszuXsyK4TH4mOENKJ45mwOyS0g%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001217&contentid=ch00000000000000001217&videoid=ch00000090990000001090&recommendtype=0&userid=1684165009466&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=CHD4K480U29XXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO&IASHttpSessionId=RR20448120260101155237039829&ispcode=55', 'mpd', 31363231393131363337323232353030, '56783536726130576e5a4171564c3741', 'general', true, 70, '2026-01-21 13:32:47.25888+00', '2026-04-08 02:51:04.450563+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, '["backup","primary","backup2","backup3","backup4","backup5","backup6"]', NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('88825c55-501d-45e7-a8be-3aa3c0cd9e99', 'Wil TV', 'https://entertainment.inquirer.net/files/2025/11/32691E59-4163-42CF-BFE3-FAB91DB8CF20.jpeg', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/wiltv/default/index.mpd', 'mpd', 'b1773d6f982242cdb0f694546a3db26f', 'ae9a90dbea78f564eb98fe817909ec9a', 'general', true, 0, '2026-02-15 10:06:43.054138+00', '2026-04-08 02:51:54.481072+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('767b32fd-af2a-445c-a07f-1f756702aba4', 'Alltv', 'https://brandlogo.org/wp-content/uploads/2024/05/All-TV-Logo-300x300.png.webp', 'http://136.239.173.2:6610/001/2/ch00000090990000001179/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20TsXah2%2FZLFNNIdWrVrXDMAow35sHUcBhGBpxqddBGYEnsyK4TH4mOENKJ45mwOyS0g%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001415&contentid=ch00000000000000001415&videoid=ch00000090990000001179&recommendtype=0&userid=1260075967329&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=HKF4YXSGDBXXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO&IASHttpSessionId=RR20453020260101155239201657&ispcode=55', 'mpd', NULL, NULL, 'general', true, 0, '2026-02-02 13:43:21.410106+00', '2026-04-08 14:29:43.44835+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, '["backup2","primary","backup","backup3","backup4","backup5","backup6"]', NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('bbe99a79-54d7-43e5-977e-c210993d2ed9', 'Hunter x Hunter', 'https://www.pngmart.com/files/23/Hunter-X-Hunter-Logo-PNG.png', 'https://www.youtube.com/embed/Yzqc6GIkSyQ?autoplay=1', 'youtube', NULL, NULL, 'general', false, 0, '2026-01-22 07:38:27.27767+00', '2026-05-13 11:55:25.605615+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('30ad56d2-1770-4eea-94de-f8a80da39ba6', 'ABC Australia', 'https://i.imgur.com/480rU5C.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/abc_aus/default/index.mpd', 'mpd', 'd6f1a8c29b7e4d5a8f332c1e9d7b6a90', '790bd17b9e623e832003a993a2de1d87', 'news', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:49:37.426637+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('a4ba8175-478c-4ff0-98b7-a3f795cf4727', 'Aniplus', 'https://i.ibb.co/N2WkpBbJ/Gemini-Generated-Image-dwpwypdwpwypdwpw.png', 'https://amg18481-amg18481c1-amgplt0352.playout.now3.amagi.tv/playlist/amg18481-amg18481c1-amgplt0352/playlist.m3u8', 'hls', NULL, NULL, 'Anime', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:49:47.599603+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('a44bf998-9e4c-46c5-bb51-2dd9c3bc4bda', 'Ani-Blast', 'https://ibb.co/8Dt5rCtQ', 'https://amg19223-amg19223c9-amgplt0352.playout.now3.amagi.tv/playlist/amg19223-amg19223c9-amgplt0352/playlist.m3u8', 'hls', NULL, NULL, 'Anime', true, 0, '2026-02-19 13:59:47.271426+00', '2026-05-18 04:19:12.791933+00', NULL, NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('33129626-48ea-46a8-9158-66090a04a5b2', 'Cartoon Classics', 'https://static.wikia.nocookie.net/logopedia/images/8/8e/Cartoon_Classics_Print.svg/revision/latest?cb=20230929014759', 'https://streams2.sofast.tv/v1/master/611d79b11b77e2f571934fd80ca1413453772ac7/d5543c06-5122-49a7-9662-32187f48aa2c/manifest.m3u8', 'hls', NULL, NULL, 'kids', true, 0, '2026-02-19 13:59:47.271426+00', '2026-05-13 11:50:02.312837+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('ff10cbe4-09a1-47c4-8b67-9116337d9eb2', 'Billiard TV', 'https://th.bing.com/th/id/OIP.JKBoiu3cX_PVMSwZLYFxCAHaHa?rs=1&pid=ImgDetMain', 'https://1b29dd71cd5e4191a3eb26afff631ed3.mediatailor.us-west-2.amazonaws.com/v1/master/9d062541f2ff39b5c0f48b743c6411d25f62fc25/SportsTribal-BilliardTV/BILLIARDTV_SCTE.m3u8', 'hls', NULL, NULL, 'Sports', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:49:55.781283+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('353db47f-50f2-4d95-acec-8d0908d261fa', 'Blast Movies', 'https://i.ibb.co/G3sSvQmD/unnamed-2.png', 'https://amg19223-amg19223c7-amgplt0351.playout.now3.amagi.tv/playlist/amg19223-amg19223c7-amgplt0351/playlist.m3u8', 'hls', NULL, NULL, 'Movies', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:49:55.942992+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('762d107f-10d3-4847-a1e4-3907d1689d32', 'Blast Sports', 'https://is1-ssl.mzstatic.com/image/thumb/Purple112/v4/62/d2/16/62d216ec-1c2f-0e1f-530e-0bdb23150ea2/AppIcon-0-0-1x_U007emarketing-0-10-0-0-85-220.png/1200x630wa.png', 'https://amg19223-amg19223c1-amgplt0351.playout.now3.amagi.tv/playlist/amg19223-amg19223c1-amgplt0351/playlist.m3u8', 'hls', NULL, NULL, 'sports', false, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:49:58.449802+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('18c8ab24-76f3-44e3-b867-9d6bc0abc8b3', 'DZRH TV', 'https://static.wikia.nocookie.net/russel/images/6/62/DZRH_TV_Logo_November_2021.png/revision/latest?cb=20211215134648', 'https://www.youtube.com/embed/live_stream?channel=UCcTiBX8js_djhSSlmJRI99A', 'youtube', NULL, NULL, 'news', true, 0, '2026-02-19 14:01:30.092577+00', '2026-04-08 02:50:18.594253+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('e4e32093-cd9b-4a8f-aa07-e56e5b3c696a', 'SMNI', 'https://i.imgur.com/WL2ugeZ.png', 'http://136.239.173.10:6610/001/2/ch00000090990000001155/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2Bop4OXrlwmfDc6Bu48vA%2B4AytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001335&contentid=ch00000000000000001335&videoid=ch00000090990000001155&recommendtype=0&userid=1436446282400&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=ZCER3GW1NZPXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', NULL, NULL, 'general', true, 0, '2026-03-10 07:22:06.586291+00', '2026-04-08 02:51:21.43846+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('91f0e199-5e5a-4910-a0c1-b09d80dab9fe', 'TVUP', 'https://i.imgur.com/3L0yn52.png', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/tvup_prd/default/index.mpd', 'mpd', 'e6d1f4a82b9c4f7e9a135c8d7b0e1f26', 'a5ec27f2fd8e81e7ca224b22a326c8f2', 'education', false, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:50.499615+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'offline', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('67023b72-4b8e-449c-a90b-24a3ddf715f8', 'Evolution Earth', NULL, 'https://amg26277-amg26277c6-samsung-ph-11091.playouts.now.amagi.tv/playlist.m3u8', 'hls', NULL, NULL, 'general', true, 0, '2026-03-20 03:11:58.059071+00', '2026-04-08 02:50:23.696306+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('ffec1f64-87cf-4392-8ab8-93968ed8d8d4', 'GMA Life TV', 'https://tse3.mm.bing.net/th/id/OIP.HpKkv2iTbDKmWpYintzOxQAAAA?rs=1&pid=ImgDetMain&o=7&rm=3', 'https://abslive.akamaized.net/dash/live/2099522/glife3/manifest.mpd', 'mpd', '5d308ef487f54107b7da758e195ecbd3', '9d4004d4c065dd4b85ad5bd12c35386f', 'general', true, 0, '2026-03-17 11:20:14.993037+00', '2026-04-08 02:50:30.184577+00', 'clearkey', NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('e6527631-f7e4-4336-bab7-f23b4435ec52', 'Hits Movies', 'https://tse2.mm.bing.net/th/id/OIP.IVTdT_KbbSE3puMAYpFGaQAAAA?cb=12&w=434&h=284&rs=1&pid=ImgDetMain&o=7&rm=3', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/hitsmovies/default/index.mpd', 'mpd', 'f56b57b32d7e4b2cb21748c0b56761a7', '3df06a89aa01b32655a77d93e09e266f', 'Movies', true, 0, '2026-02-19 14:03:15.902679+00', '2026-04-08 02:50:42.367126+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('ff347170-9e1e-4773-8057-6a244801afff', 'Cinemo! Global', 'https://ottepg8.comclark.com:8443/iptvepg/images/markurl/mark_1723219276891.png', 'https://cdn-ue1-prod.tsv2.amagi.tv/linear/amg01006-abs-cbn-cinemo-dash-abscbnono/index.mpd', 'mpd', 'aa8aebe35ccc4541b7ce6292efcb1bfb', 'f06b6031a3604cc6708c14d83f1a1b27', 'Movies', true, 0, '2026-02-19 13:59:47.271426+00', '2026-05-15 01:03:57.214786+00', 'clearkey', 'https://iptvproxy-five.vercel.app/api/license?url=https://ottmdrm.comclark.com/widevine/', NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('06400e94-1ab9-4f63-bd9f-bfb7797c42d8', 'YTV', 'https://i.imgur.com/LXoPZ8x.png', 'https://a196aivottlinear-a.akamaihd.net/OTTB/pdx-nitro/live/clients/dash/enc/o7aqpbb6vv/out/v1/f8f6ef738ef24c4f8176d561ffb8a157/cenc.mpd', 'mpd', '6f0aeae5779f1dcaef23f0bfbc828220', '7bcef3cf93de00e3daeb190d15b1ec05', 'general', true, 0, '2026-05-14 03:41:17.724739+00', '2026-05-14 03:41:17.724739+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('f774f860-7ca5-4e14-9e05-a12244b47180', 'ONE Championship', 'https://logowik.com/content/uploads/images/one-championship2775.jpg', 'https://live-pv-ta.amazon.fastly-edge.com/syd-nitro/live/clients/dash/enc/kkfdbi2d1c/out/v1/a5b9b32dafd5499688240287ef8c9b90/cenc.mpd', 'mpd', '308006101c8fd0262c0f529319b9c127', '37683aadc75b1450efa82d62c647984d', 'general', true, 0, '2026-03-08 11:46:00.772564+00', '2026-04-08 02:51:09.439339+00', 'clearkey', NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('c2e4a1bb-0847-4e91-b096-b751d2c5cfd8', 'RPTV', 'https://th.bing.com/th/id/OIP.hWUhA4FmrinqMTykADb9NwHaEX?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/cnn_rptv_prod_hd/default/index.mpd', 'mpd', '1917f4caf2364e6d9b1507326a85ead6', 'a1340a251a5aa63a9b0ea5d9d7f67595', 'news', true, 0, '2026-02-19 14:04:59.209157+00', '2026-04-08 02:51:19.819678+00', 'clearkey', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('84ea1970-9eef-466b-a9f8-075e5cae46f7', 'Bein Sports 2', 'https://upload.wikimedia.org/wikipedia/commons/7/78/Logo_beIN_SPORTS_2.png', 'https://unifi-live2.secureswiftcontent.com/Content/DASH/Live/channel(bein2)/master.mpd', 'mpd', 'efa6ff1acefa43048e8b7adc21d98871', '5d0f448b52a92035e3763c4a60275933', 'general', false, 0, '2026-03-19 10:31:02.646671+00', '2026-04-08 02:57:40.557263+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', 'VPN REQUIRED!', 'Kailangan ng VPN (Singapore) Para mag play', 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('36c86cf3-7bb8-4a0d-88c2-9d1d8fd3c400', 'Rock Entertainment', 'https://assets-global.website-files.com/64e81e52acfdaa1696fd623f/652f763c600497122b122df0_logo_ent_red_web.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/dr_rockentertainment/default/index.mpd', 'mpd', 'e4ee0cf8ca9746f99af402ca6eed8dc7', 'be2a096403346bc1d0bb0f812822bb62', 'entertainment', true, 0, '2026-02-19 14:04:59.209157+00', '2026-05-14 06:13:06.317579+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('6ce4a149-0b16-4759-b086-ea57a440a4fb', 'Asian Crush', 'https://grasshopperfilm.com/wp-content/uploads/2016/05/Asian-Crush-LOGO-GRAY.png', 'https://cineverse.g-mana.live/media/1ebfbe30-c35c-4404-8bc5-0339d750eb58/mainManifest.m3u8', 'hls', NULL, NULL, 'general', true, 0, '2026-02-22 11:08:56.700787+00', '2026-04-08 02:49:47.479375+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('6fe5ccde-0d27-441c-9572-2346751cd580', 'TV Maria', 'https://static.wikia.nocookie.net/logopedia/images/c/cd/TV_MARIA_PH.png/revision/latest?cb=20200421061144', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/tvmaria_prd/default/index.mpd', 'mpd', 'fa3998b9a4de40659725ebc5151250d6', '998f1294b122bbf1a96c1ddc0cbb229f', 'general', true, 0, '2026-03-12 01:27:03.681231+00', '2026-04-08 02:51:48.447553+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('0c2a56f5-4c63-4ef2-a1ca-46fd05ce016f', 'TSN2', 'https://r2.thesportsdb.com/images/media/channel/fanart/9wma511726868598.jpg', 'https://tv.city.bg/play/tshls/citytv/index.m3u8', 'hls', NULL, NULL, 'general', true, 0, '2026-03-22 09:56:43.543224+00', '2026-04-08 02:51:43.765557+00', NULL, NULL, NULL, false, NULL, NULL, 'tsn2', 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('703edb57-b0b7-453a-bf9d-6f15827f5102', 'Bein Sports 3', 'https://www.programme-tv.net/imgre/fit/~2~channel~0f3f6494879ee619.png/1200x630/crop-from/top/quality/80/bein-sports-3.png', 'https://unifi-live2.secureswiftcontent.com/Content/DASH/Live/channel(bein3)/master.mpd', 'mpd', '816ee2f7c19f49ed84276f34541b465b', 'ca764a9973b6123a1112cffd3b32010d', 'general', false, 0, '2026-03-19 10:33:15.566078+00', '2026-04-08 02:57:47.210949+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', 'VPN REQUIRED!', 'Kailangan ng VPN (Singapore) Para mag play', 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('f25ed624-9678-4cd4-9c6c-c5e18583cf7a', 'GMA Pinoy TV', 'https://th.bing.com/th/id/OIP.ntjNVRaXsZJ0vrhWBA35sQHaE7?rs=1&pid=ImgDetMain', 'https://abslive.akamaized.net/dash/live/2099522/gmapt3/manifest.mpd', 'mpd', '7b5d15a7385546768aca9fd505ad5e16', 'f534393c84c1a9c17fa36bc3a4380981', 'entertainment', true, 0, '2026-02-19 14:01:30.092577+00', '2026-04-08 02:50:29.904775+00', 'clearkey', NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('f4d399a5-9b0f-4242-a5e6-61aa93356f33', 'Arirang', 'https://www.liblogo.com/img-logo/ar4639a640-arirang-logo-arirang-south-korea--com-watch-1000-free-tv-channel.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/arirang_sd/default/index.mpd', 'mpd', '13815d0fa026441ea7662b0c9de00bcf', '2d99a55743677c3879a068dd9c92f824', 'general', true, 0, '2026-03-14 01:28:33.15297+00', '2026-04-08 02:49:46.864645+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('3fdf2439-deca-4cf4-8714-14fbb948105b', 'TV5 Monde', 'https://klean.nl/wp-content/uploads/Logo_TV5_Monde_-_2021.svg_.png', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/dr_tv5_monde/default/index.mpd', 'mpd', 'fba5a720b4a541b286552899ba86e38b', 'f63fa50423148bfcbaa58c91dfcffd0e', 'general', true, 0, '2026-03-14 01:31:53.058245+00', '2026-05-15 01:34:03.787071+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('c6adc755-212d-4207-97a3-cfc3508654af', 'IBC13', 'https://th.bing.com/th/id/OIP.sJNkdFUalhzRyZT4SJ9HBAHaEc?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/ibc13_sd_new/default1/index.mpd', 'mpd', '16ecd238c0394592b8d3559c06b1faf5', '05b47ae3be1368912ebe28f87480fc84', 'entertainment', true, 0, '2026-02-19 14:03:15.902679+00', '2026-04-08 02:50:46.979793+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('c4225682-57de-4ea8-833b-aefe7605b9f7', 'Bein Sports 4', 'https://tse1.mm.bing.net/th/id/OIP.uaJKrXeD_QgJG8wQZ_REWgHaBG?rs=1&pid=ImgDetMain&o=7&rm=3', 'https://unifi-live2.secureswiftcontent.com/Content/DASH/Live/channel(bein4)/master.mpd', 'mpd', 'd561ff976397473e9b456b44cdffcdd2', '2b6cff42f7fae7e8bc32f3d5c62dc3c2', 'general', false, 0, '2026-03-19 10:34:28.301302+00', '2026-04-08 02:57:55.569929+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', 'VPN REQUIRED!', 'Kailangan ng VPN (Singapore) Para mag play', 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('f25848d7-ef7d-4120-a0fd-a834794403b5', 'Disney Channel', 'https://th.bing.com/th/id/OIP.ry79quPYFII7hj-ZpuoDAQHaDt?rs=1&pid=ImgDetMain', 'https://thetvapp.to/tv/espnu-live-stream/', 'hls', '72800c62fcf2bfbedd9af27d79ed35d6', 'b6ccb9facb2c1c81ebe4dfaab8a45195', 'kids', true, 0, '2026-02-19 14:01:30.092577+00', '2026-04-08 02:50:16.717532+00', NULL, NULL, NULL, false, NULL, NULL, 'DisneyChannelEast', 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('5d85cf2c-4bdb-4f03-9472-121498cc6206', 'Universal', 'https://seeklogo.com/images/U/universal-tv-logo-E785C73128-seeklogo.com.png', 'https://bks400-tol-110.quieroxview.com.mx/bpk-tv/universal_hd/default/index.mpd', 'mpd', '52358519f886446d82834a803b36f796', '58b6ac8e07d354b178255e03b9d0f819', 'general', true, 0, '2026-03-05 10:54:30.519754+00', '2026-04-08 02:51:52.319526+00', 'clearkey', NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('0eccdf9f-7f92-46c2-8581-7aedb23fbd41', 'Jeepney TV', 'https://static.wikia.nocookie.net/russel/images/0/0b/Jeepney_TV_3D_Logo_2015.png', 'https://abslive.akamaized.net/dash/live/2027618/jeepneytv/manifest.mpd', 'mpd', 'dc9fec234a5841bb8d06e92042c741ec', '225676f32612dc803cb4d0f950d063d0', 'general', true, 0, '2026-02-02 13:47:49.399477+00', '2026-05-15 01:32:12.043916+00', 'clearkey', 'https://iptvproxy-five.vercel.app/api/license?url=https://ottmdrm.comclark.com/widevine/', NULL, false, NULL, '["backup3","primary","backup","backup2","backup4"]', NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('b0d87260-2105-4854-b6f8-db5d81104469', 'Discovery Science', 'https://banner2.cleanpng.com/20180824/ava/kisspng-science-channel-logo-discovery-channel-brand-showing-porn-images-for-greek-italian-porn-www-fre-1713949227223.webp', 'https://d1g8wgjurz8via.cloudfront.net/bpk-tv/Discoveryscience2/default/manifest.mpd', 'mpd', '5458f45efedb4d6f8aa6ac76c85b621b', 'dbf8a0a306a64525ba3012fd225370c0', 'documentary', true, 0, '2026-02-19 14:01:30.092577+00', '2026-04-08 02:50:16.788764+00', 'clearkey', NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('c628fbe7-8c8d-4edc-bee7-c88e9ecfc0a8', 'ESPNU ', 'https://logodix.com/logo/1086856.png', 'https://thetvapp.to/tv/espnu-live-stream/', 'hls', NULL, NULL, 'Sports', true, 10, '2026-03-09 03:31:38.786928+00', '2026-04-08 02:50:21.057816+00', NULL, NULL, NULL, false, NULL, '["backup4","primary","backup","backup2","backup3"]', 'ESPNU', 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('ede7f5d8-b736-4f7f-aacf-ad436fa47b45', 'Fashion TV HD', 'https://th.bing.com/th/id/OIP.fRG_3Wx6qmssHxgeN5leBQHaD4?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/fashiontvhd/default/index.mpd', 'mpd', '9d7c1f2a6b4e4a8d8f33c1e5b7d2a960', '3a18c535c52db7c79823f59036a9d195', 'entertainment', true, 0, '2026-02-19 14:01:30.092577+00', '2026-04-08 02:50:23.004128+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('301b2844-c1ff-42f7-8292-88df3262ac35', 'GMA (Youtube Stream)', 'https://aphrodite.gmanetwork.com/entertainment/shows/images/1200_675_TVShow_MainTCARD_-20220622115633.png', 'https://www.youtube.com/embed/live_stream?channel=UCKL5hAuzgFQsyrsQKgU0Qng', 'youtube', NULL, NULL, 'entertainment', true, 0, '2026-02-19 14:01:30.092577+00', '2026-04-08 02:50:27.634652+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('e708fc4f-c931-42d9-b88d-acd034cfa317', 'GMA News TV', 'https://th.bing.com/th/id/OIP.rziiLbLj2AZSThcW3EQ0uAHaHa?o=7rm=3&rs=1&pid=ImgDetMain&o=7&rm=3', 'https://abslive.akamaized.net/dash/live/2099522/gnews3/manifest.mpd', 'mpd', 'd5d848730e4a4f9b962290039dd2b96b', 'c959dc12f1bff5a66d030117fb7e9855', 'general', true, 0, '2026-03-17 11:22:11.355894+00', '2026-04-08 02:50:29.875027+00', 'clearkey', NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('adfc342b-0428-41b1-8ef0-d1f284c49d3b', 'Star TV Philippines ', NULL, 'https://startvphilippines.sanmateocable.workers.dev/playlist.m3u8', 'hls', NULL, NULL, 'general', false, 0, '2026-03-15 04:58:23.100936+00', '2026-04-08 02:51:27.695188+00', NULL, NULL, NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('b6e84779-2086-433e-8bd1-0a143496c54f', 'TBN ASIA', 'https://avpn.asia/wp-content/uploads/2018/07/TBN-Asia-Logo.jpg', 'http://136.239.158.30:6610/001/2/ch00000090990000001147/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2Br1gDY5x7IZ%2FDqQTvxeS3W1ytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001317&contentid=ch00000000000000001317&videoid=ch00000090990000001147&recommendtype=0&userid=1315480960661&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=IK7JAFC7DFXXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', NULL, NULL, 'general', true, 0, '2026-03-21 10:55:08.699369+00', '2026-04-08 02:51:31.741266+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, '["backup2","primary","backup","backup3","backup4","backup5","backup6"]', NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('ec035530-ad30-48d2-8262-910ce83c9968', 'KpopTV Play', 'https://i.imgur.com/Tf0vweF.png', 'https://giatv.bozztv.com/giatv/giatv-kpoptvplay/kpoptvplay/playlist.m3u8', 'hls', NULL, NULL, 'general', true, 0, '2026-05-15 10:55:08.005469+00', '2026-05-15 10:55:08.005469+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('89b18872-ada1-49c8-94cf-9b32941a021f', 'K-Movies', 'https://th.bing.com/th/id/OIP.uvYKFBubGFR40NtgWh7W8wHaES?rs=1&pid=ImgDetMain', 'https://7732c5436342497882363a8cd14ceff4.mediatailor.us-east-1.amazonaws.com/v1/master/04fd913bb278d8775298c26fdca9d9841f37601f/Plex_NewMovies/playlist.m3u8', 'hls', NULL, NULL, 'movies', false, 0, '2026-02-19 14:03:15.902679+00', '2026-04-08 02:50:48.995473+00', NULL, NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'offline', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('d956e883-1be7-4f9a-b3ec-7b29077a0b7a', 'iQIYI', 'https://th.bing.com/th/id/OIP.tGUjHFJqDIFUuKfn-31TxAHaEN?rs=1&pid=ImgDetMain', 'https://mt12.aa.astro.com.my/default_ott.mpd?PID=&PAID=1006&deviceIdType=%5BdevIdType%5D&deviceId=1&appId=astrogo.astro.com.my&appName=%5BappName%5D&devModel=%5BdevModel%5D&playerWidth=%5BplayerWidth%5D&playerHeight=%5BplayerHeight%5D&sessionId=abr-linear-1&optin=true&hhid=1&kvp=lang%7Echi&kvp=genre%7ECHINESE%2CHD%2CALL&daiEnabled=true', 'mpd', '7ef7e913ce85a1131b27036069169a10', '77d98ed71db7524c27875a09a975f9e6', 'entertainment', false, 0, '2026-02-19 14:03:15.902679+00', '2026-05-13 11:55:15.576459+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('9106aba4-0c44-4b81-a5ed-605a154ce7bf', 'Studio Universal', 'https://www.seekpng.com/png/detail/336-3361501_studio-universal-channel-logo.png', 'https://bks400-tol-110.quieroxview.com.mx/bpk-tv/studio_universal_hd/default/index.mpd', 'mpd', '52358519f886446d82834a803b36f796', '58b6ac8e07d354b178255e03b9d0f819', 'general', true, 0, '2026-03-05 10:58:20.313888+00', '2026-04-08 02:51:28.071234+00', 'clearkey', NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('e74e6078-d231-448d-8d8b-6e2013227ed2', 'Spotlight', 'https://static.wikia.nocookie.net/dreamlogos/images/3/32/Spotlight.png', 'http://136.239.158.30:6610/001/2/ch00000090990000001134/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2Bo5iGQ4tDytzSdpM9ehJW6pytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001281&contentid=ch00000000000000001281&videoid=ch00000090990000001134&recommendtype=0&userid=1790262524603&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=MG695A5LWR8XXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', NULL, NULL, 'general', true, 0, '2026-03-14 01:37:42.959751+00', '2026-04-08 02:51:25.68905+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('39061677-6b32-4dcf-960f-2ffded3b579e', 'Jungo Pinoy tv', 'https://dito.ph/hubfs/Dito_July2021/Ott%20Pages/Jungo-img/Jungo-logo.png', 'https://jungotvstream.chanall.tv/jungotv/jungopinoytv/stream.m3u8', 'hls', NULL, NULL, 'entertainment', false, 0, '2026-02-19 14:03:15.902679+00', '2026-04-08 02:50:48.965881+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'offline', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('d9d3428c-ac9d-4355-8bb6-51ee7cd302de', 'Kapamilya Channel', 'https://i.imgur.com/WcYS3S3.png', 'https://cdn-ue1-prod.tsv2.amagi.tv/linear/amg01006-abs-cbn-kapcha-dash-abscbnono/manifest.mpd', 'mpd', '292dee4236d04054910e9706ee22626b', 'b7c5d3220f6eb6e042a2bcb367b5c09b', 'entertainment', true, 0, '2026-02-19 14:03:15.902679+00', '2026-05-15 03:02:23.370846+00', 'clearkey', NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('d7f54275-9085-4c41-9a91-5a0c777bfaa0', 'cctv4', 'https://images.now-tv.com/shares/channelPreview/img/en_hk/color/ch542_170_122', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/dr_cctv4/default/index.mpd', 'mpd', 'b83566836c0d4216b7107bd7b8399366', '32d50635bfd05fbf8189a0e3f6c8db09', 'general', true, 0, '2026-03-19 11:05:45.214951+00', '2026-05-13 11:48:02.95132+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('43030e8e-2d75-426a-9c6c-2103e613f18a', 'One Sports', 'https://vignette.wikia.nocookie.net/logopedia/images/5/56/TV5_One_Sports_Channel.png/revision/latest/scale-to-width-down/300?cb=20181221055916', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_onesports_hd/default/index.mpd', 'mpd', '53c3bf2eba574f639aa21f2d4409ff11', '3de28411cf08a64ea935b9578f6d0edd', 'Sports', true, 0, '2026-02-19 14:04:59.209157+00', '2026-04-08 02:51:11.544362+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('eb3d9f51-7ee7-4665-a72d-7bfcb36a4c23', 'Kapamilya Online', 'https://th.bing.com/th/id/OIP.WJ42CLSN52F8__yoFceMOwHaEK?rs=1&pid=ImgDetMain', 'https://www.youtube.com/embed/live_stream?channel=UCstEtN0pgOmCf02EdXsGChw', 'youtube', NULL, NULL, 'entertainment', true, 0, '2026-02-19 14:03:15.902679+00', '2026-04-08 02:50:50.871046+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('8dfb55b9-f276-4f41-862d-81d9d954d609', 'Kplus', 'https://www.pngkey.com/png/detail/306-3060351_k-plus-k-plus-channel-logo.png', 'http://linearjitp-playback.astro.com.my/dash-wv/linear/9983/default_ott.mpd', 'mpd', 'aa48b28bd723f91214887df6ed9fad10', 'b5a3a800848120c843ae0fa68c09c261', 'kids', true, 0, '2026-02-19 14:03:15.902679+00', '2026-05-15 10:46:17.104701+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'supabase', 'VPN REQUIRED!', 'Kailangan ng VPN (Singapore) Para mag play', 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('c2dffb21-dcf7-435b-89cb-1bea77e6ccf0', 'PBA Rush', 'https://th.bing.com/th/id/OIP.dDzYufwVTWroitJQy9pfXQAAAA?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_pbarush_hd1/default/index.mpd', 'mpd', 'd7f1a9c36b2e4f8d9a441c5e7b2d8f60', 'fb83c86f600ab945e7e9afed8376eb1e', 'Sports', true, 0, '2026-02-19 14:04:59.209157+00', '2026-04-08 02:51:13.587748+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('7e8882ad-90ec-4671-bc56-89b9b9d188a1', 'SolarFlix', 'https://i.imgur.com/OgBDJ75.png', 'http://136.239.173.2:6610/001/2/ch00000090990000001243/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20TsXah2%2FZLFNNIdWrVrXDMApbUxUxZzyq5Czg7gUnQAcvsyK4TH4mOENKJ45mwOyS0g%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001543&contentid=ch00000000000000001543&videoid=ch00000090990000001243&recommendtype=0&userid=1701764478515&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=X2HJNQYJ1AXXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO&IASHttpSessionId=RR20447120260101155240008753&ispcode=55', 'mpd', NULL, NULL, 'general', true, 0, '2026-02-02 13:46:43.076378+00', '2026-04-08 02:51:23.468712+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('b5b73aeb-39e7-4f4b-967e-32e0fc0977e1', 'TNT SPORTS 1 UK', 'https://r2.thesportsdb.com/images/media/channel/logo/153ikz1689746051.png', 'https://otte.live.fly.ww.aiv-cdn.net/gru-nitro/live/dash/enc/cllekigzzn/out/v1/bd3b0c314fff4bb1ab4693358f3cd2d3/cenc.mpd', 'mpd', '294b5761cefc22d0c6312939e13d8278', '52148f1042d238849f0a7813f1da8a7b', 'general', true, 0, '2026-03-19 04:09:05.397696+00', '2026-04-08 02:51:37.433274+00', 'clearkey', NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('48aa8063-9de7-4a8b-8eb3-ba1097e462d2', 'ESPN', 'https://1000logos.net/wp-content/uploads/2021/02/ESPN-logo.jpg', 'https://thetvapp.to/tv/espn-live-stream/', 'hls', NULL, NULL, 'general', true, 0, '2026-03-09 03:59:56.128546+00', '2026-04-08 02:50:20.783301+00', NULL, NULL, NULL, false, NULL, NULL, 'ESPN', 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('76a377e8-9727-4c0b-ac40-4a85b319eea1', 'EWTN', 'https://www.ewtn.com/img/ewtn-logo.jpg', 'http://136.239.158.18:6610/001/2/ch00000090990000001104/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2Brqe%2B6z8S0P4H4d709E7gynytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001180&contentid=ch00000000000000001180&videoid=ch00000090990000001104&recommendtype=0&userid=1130713546686&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=FGMTXNDRQLDXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', NULL, NULL, 'general', true, 0, '2026-03-21 10:39:14.423969+00', '2026-04-08 02:50:22.843498+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('0d6e3f72-60fc-4b79-bedf-35c2ffbc8c09', 'TSN3', 'https://r2.thesportsdb.com/images/media/channel/fanart/9wma511726868598.jpg', 'https://tv1.cloudcdn.bg/temp/livestream.m3u8', 'hls', NULL, NULL, 'general', false, 0, '2026-03-22 09:57:10.225651+00', '2026-04-08 02:51:46.501849+00', NULL, NULL, NULL, false, NULL, NULL, 'tsn3', 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('32d60307-382c-4630-a006-dba4c1a20709', 'INC TV', 'https://i.imgur.com/b6JmGBq.png', 'http://136.239.159.18:6610/001/2/ch00000090990000001092/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2BrC5ZD%2FYbS0KSGrFVJUNIMkytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001178&contentid=ch00000000000000001178&videoid=ch00000090990000001092&recommendtype=0&userid=1760058453659&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=HILNO5G9U9IXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', NULL, NULL, 'general', true, 0, '2026-03-12 01:36:06.494835+00', '2026-04-08 02:50:46.50258+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('92403af1-d280-449f-8be3-836c11982011', 'Teleradyo', 'https://i.imgur.com/npj41pk.png', 'https://cdn-ue1-prod.tsv2.amagi.tv/linear/amg01006-abs-cbn-teleradyo-dash-abscbnono/index.mpd', 'mpd', '47c093e0c9fd4f80839a0337da3dd876', '603248b858276f533a13e17f2f48c711', 'news', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:32.341762+00', 'clearkey', 'https://ottmdrm.comclark.com/widevine/', NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('c4905f33-4c33-4cc0-add6-d2d5aff9a186', 'Discovery Kids', NULL, 'https://bks400-tol-110.quieroxview.com.mx/bpk-tv/discovery_kids_hd/default/index.mpd', 'mpd', '52358519f886446d82834a803b36f796', '58b6ac8e07d354b178255e03b9d0f819', 'general', true, 0, '2026-03-05 11:05:27.549699+00', '2026-04-08 02:50:14.073031+00', 'clearkey', NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('1b2612eb-7ed4-4ce2-b661-6b311582cef9', 'Light TV', 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTPkvWEPQltk-Xq-ixCjPdOGxoqgIlMsc095A&s', 'http://136.239.159.20:6610/001/2/ch00000090990000001103/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2BqkZ6SnNx3gh97OtxQ2ygibytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001179&contentid=ch00000000000000001179&videoid=ch00000090990000001103&recommendtype=0&userid=1847927235474&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=FR3HWWBCXEEXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', NULL, NULL, 'general', true, 0, '2026-03-21 10:58:38.565863+00', '2026-04-08 02:50:58.575765+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, '["backup2","primary","backup","backup3","backup4","backup5","backup6"]', NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('a0be95d0-b178-4495-a0c6-43055a8eaa47', 'Mindanow Network', 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTqndReZ8wqIcJO39ZUlQnjeayPJ-11_bVnow&s', 'http://136.239.173.26:6610/001/2/ch00000090990000001123/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2BrWYLxykQwHejqAgxTqFbr7ytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001237&contentid=ch00000000000000001237&videoid=ch00000090990000001123&recommendtype=0&userid=1545743380024&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=7NAS0TOF95HXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', NULL, NULL, 'general', true, 0, '2026-03-21 10:46:09.307136+00', '2026-04-08 02:51:00.449932+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, '["backup2","primary","backup","backup3","backup4","backup5","backup6"]', NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('b4b57dbd-bd12-49bc-a8ca-05d5a7104509', 'Rakuten Viki', 'https://tse1.mm.bing.net/th/id/OIP.14iQmo2HrOxiL10lttVslgAAAA?rs=1&pid=ImgDetMain&o=7&rm=3', 'https://fd18f1cadd404894a31a3362c5f319bd.mediatailor.us-east-1.amazonaws.com/v1/master/04fd913bb278d8775298c26fdca9d9841f37601f/RakutenTV-eu_RakutenViki-1/playlist.m3u8', 'hls', NULL, NULL, 'entertainment', true, 0, '2026-02-19 14:04:59.209157+00', '2026-04-08 02:51:17.773146+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('2c40ffc0-ecf8-4a72-90c7-7099f3f2e30f', 'Red Bull TV', 'https://i.ibb.co/cK5FsbyM/unnamed-1.png', 'https://d3k3xxewhm1my2.cloudfront.net/playlist.m3u8', 'hls', NULL, NULL, 'sports', true, 0, '2026-02-19 14:04:59.209157+00', '2026-04-08 02:51:17.868117+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('4b4a7ecf-a5e8-4df5-9956-e23847009ebd', 'SineManila', 'https://i.imgur.com/zcFUYC5.png', 'https://live20.bozztv.com/giatv/giatv-sinemanila/sinemanila/chunks.m3u8', 'hls', NULL, NULL, 'movies', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:21.671127+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('28dc5970-3dc5-4a6b-b48a-b499dd6ace28', 'Sony Cine', 'https://th.bing.com/th/id/OIP._NGk-Rpn5n6TOVRIjvnZ6QHaHb?rs=1&pid=ImgDetMain', 'https://a-cdn.klowdtv.com/live1/cine_720p/chunks.m3u8', 'hls', NULL, NULL, 'movies', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:23.808277+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('b4b6b382-dc29-4ed3-9aa8-af427c2640bc', 'Tap Action Flix', 'https://i.ibb.co/wgjPKFW/IMG-20241029-111906.png', 'http://136.239.173.26:6610/001/2/ch00000090990000001305/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2BpahcUJJEYAxPtEef94INw1ytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001775&contentid=ch00000000000000001775&videoid=ch00000090990000001305&recommendtype=0&userid=1826997527749&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=BJ80X0UU6VXXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', 'bee1066160c0424696d9bf99ca0645e3', 'f5b72bf3b89b9848de5616f37de040b7', 'movies', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:27.745516+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('12ea7998-eb72-4556-b262-149d155ddf99', 'France24', 'https://i.imgur.com/61MSiq9.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/france24/default/index.mpd', 'mpd', '257f9fdeb39d41bdb226c2ae1fbdaeb6', 'e80ead0f4f9d6038ab34f332713ceaa5', 'general', true, 0, '2026-03-14 01:43:55.362229+00', '2026-04-08 02:50:25.793244+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('04084e8c-9d23-42b8-ae6c-cddc257ca3df', 'Tennis+', 'https://i.ibb.co/wNqkRfjw/unnamed.png', 'https://amg01935-amg01935c1-amgplt0352.playout.now3.amagi.tv/playlist/amg01935-amg01935c1-amgplt0352/playlist.m3u8', 'hls', NULL, NULL, 'Sports', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:34.740138+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('4d0aa71c-a5fb-44c6-bd3b-3a83df00a2ff', 'TMC', 'https://th.bing.com/th/id/OIP.mskveWFrbAwpq6athkC91gAAAA?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/cg_tagalogmovie/default/index.mpd', 'mpd', '96701d297d1241e492d41c397631d857', 'ca2931211c1a261f082a3a2c4fd9f91b', 'movies', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:36.862916+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('ab76a53b-1085-4d4f-ab4b-8fbc2d58bc7e', 'TNT SPORTS 2 UK', 'https://i.ibb.co/gFpYs4N/tnt2.png', 'https://a12aivottepl-a.akamaihd.net/gru-nitro/live/dash/enc/fb6jy4pxts/out/v1/f8fa17f087564f51aa4d5c700be43ec4/cenc.mpd', 'mpd', 'f288380ca4cef9ad3f27a92a08e9bb8b', '9f18d26291d9230833501f7f822f6875', 'general', true, 0, '2026-03-19 04:11:06.793129+00', '2026-04-08 02:51:36.921493+00', 'clearkey', NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('fa2facd3-f502-42d8-8df4-871c8f231853', 'BUKO', 'https://th.bing.com/th/id/OIP.ph_7Uv-meouzQBVcfuuQQwHaIL?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_buko_sd/default/index.mpd', 'mpd', 'd273c085f2ab4a248e7bfc375229007d', '7932354c3a84f7fc1b80efa6bcea0615', 'entertainment', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:49:57.838331+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('fbb7db1f-ab3f-4b15-b2bd-6d2190ba20d8', 'Travel Channel', 'https://i.imgur.com/ZCYeUV2.png', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/travel_channel_sd/default/index.mpd', 'mpd', 'f3047fc13d454dacb6db4207ee79d3d3', 'bdbd38748f51fc26932e96c9a2020839', 'documentary', true, 0, '2026-02-19 14:06:16.730317+00', '2026-05-15 01:33:25.681667+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('6c64fdbe-be1c-4a76-910a-be60fce911af', 'TSN1', 'https://r2.thesportsdb.com/images/media/channel/fanart/9wma511726868598.jpg', 'https://tv.city.bg/play/tshls/citytv/index.m3u8', 'hls', NULL, NULL, 'general', true, 0, '2026-03-22 09:56:12.133366+00', '2026-04-08 02:51:43.215945+00', NULL, NULL, NULL, false, NULL, NULL, 'tsn1', 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('1d5b6f09-5920-4d5a-8b27-5c4fe8026dbc', 'Discovery Asia', 'https://iyadtv.pages.dev/images/discovery_asia_71.png', 'https://cdn3.skygo.mn/live/disk1/Discovery_Asia/HLSv3-FTA/Discovery_Asia.m3u8', 'hls', NULL, NULL, 'general', true, 0, '2026-02-22 10:51:08.065718+00', '2026-04-08 02:50:14.35494+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('b7ccd58c-2ef6-4e61-8ae7-4d3d9214e5b6', 'Hallypop', 'https://static.wixstatic.com/media/3f6f0d_6b141fb2470c4d0d9210f6cac32075ac~mv2.png/v1/fill/w_600,h_139,al_c,q_85,usm_0.66_1.00_0.01,enc_auto/Hallypop_Logo_FullColor.png', 'http://136.158.97.2:6610/001/2/ch00000090990000001152/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20TsXah2%2FZLFNNIdWrVrXDMArQQqEzMGzqacd7xs%2FVYEXbsyK4TH4mOENKJ45mwOyS0g%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001373&contentid=ch00000000000000001373&videoid=ch00000090990000001152&recommendtype=0&userid=1445262980630&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=6BMZCB3961FXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO&IASHttpSessionId=RR20447320260101155239274438&ispcode=55', 'mpd', NULL, NULL, 'general', true, 0, '2026-02-21 10:57:47.312854+00', '2026-04-08 02:50:34.050513+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('c5ef226e-aff7-424b-a77c-0eb45348ec4c', 'Metro Channel', 'https://i.imgur.com/wAraZeF.png', 'http://136.158.97.2:6610/001/2/ch00000090990000001267/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20TsXah2%2FZLFNNIdWrVrXDMAr4hyjlpFsJWrmHS5nwWoXTsyK4TH4mOENKJ45mwOyS0g%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001549&contentid=ch00000000000000001549&videoid=ch00000090990000001267&recommendtype=0&userid=1339539301753&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=NU1C68YJPUXXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO&IASHttpSessionId=RR20446720260101155240169310&ispcode=55', 'mpd', 31363334313133373731323334343436, '673478506852336979544a4f38475479', 'general', true, 1, '2026-01-21 13:23:17.858384+00', '2026-04-08 02:51:00.446292+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, '["backup","primary","backup2","backup3","backup4","backup5","backup6"]', NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('5ec7ea46-4122-440e-9c58-19e396cbee9b', 'Moonbug Kids', 'https://aqfadtv.xyz/logos/Moonbug.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_moonbug_kids_sd/default/index.mpd', 'mpd', '0bf00921bec94a65a124fba1ef52b1cd', '0f1488487cbe05e2badc3db53ae0f29f', 'general', true, 0, '2026-03-12 10:29:06.002484+00', '2026-04-08 02:51:02.803323+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('6b821844-ddad-4501-9d48-4c73bc9de723', 'Solar Sports ', 'https://static.wikia.nocookie.net/logopedia/images/d/d1/Solar_Sports_3D_Logo_2002.png/revision/latest?cb=20250110121912', 'http://136.239.159.20:6610/001/2/ch00000090990000001081/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20TsXah2%2FZLFNNIdWrVrXDMApTfGIKxFqRM2tu30PzY%2FKksyK4TH4mOENKJ45mwOyS0g%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001087&contentid=ch00000000000000001087&videoid=ch00000090990000001081&recommendtype=0&userid=1660983599746&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=BKS53DBOW29XXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO&IASHttpSessionId=RR20445520260101155236041906&ispcode=55', 'mpd', NULL, NULL, 'Sports', true, 0, '2026-02-21 11:02:43.157341+00', '2026-04-08 02:51:23.405675+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('c8a08d79-da94-44e8-80f7-724692074825', 'Thrill', 'https://www.mncvision.id/userfiles/image/channel/thrill_150x150px.jpg', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/cg_thrill_sd/default/index.mpd', 'mpd', '928114ffb2394d14b5585258f70ed183', 'a82edc340bc73447bac16cdfed0a4c62', 'movies', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:34.251969+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('c2b9bf0f-e9d1-4f13-b64f-58558caaa877', 'TNT SPORTS 3 UK', 'https://i.ibb.co/gFpYs4N/tnt2.png', 'https://otte.live.fly.ww.aiv-cdn.net/gru-nitro/live/dash/enc/5sxuux529k/out/v1/bb548a3626cd4708afbb94a58d71dce9/cenc.mpd', 'mpd', '1d96ab366bbe6451edf7407b58e2fa16', '0116201f4a63ac5bf5787d2c610c41a7', 'general', true, 0, '2026-03-19 04:12:26.877924+00', '2026-04-08 02:51:39.710971+00', 'clearkey', NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('11edb96e-9e52-453b-9b82-369f53aa87e6', 'Love Nature', 'https://lovenature.com/wp-content/uploads/2020/08/love-nature-logo_peacock.png', 'https://unifi-live2.secureswiftcontent.com/Content/DASH/Live/channel(lovenature)/master.mpd', 'mpd', '3af2407f93664272a2b0c24be3632d93', '6504d3e04a92a7d0d0d36818f477cae4', 'general', false, 0, '2026-02-21 10:32:51.149205+00', '2026-05-14 11:34:01.810897+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'supabase', 'VPN REQUIRED!', 'Kailangan ng VPN (Singapore) Para mag play', 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('9b2d85a8-14cf-437d-ad62-525a3eb66a41', 'Euronews', 'https://images.seeklogo.com/logo-png/47/1/euronews-logo-png_seeklogo-470736.png', 'https://unifi-live2.secureswiftcontent.com/Content/DASH/Live/channel(EuroN)/master.mpd', 'mpd', '67f4948cdafa46ebbd71eae875237023', '9dc5b14da7c3c0d89d63bd9242c2dab0', 'general', true, 0, '2026-03-20 00:44:20.321508+00', '2026-04-08 02:50:20.740956+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('98bb3b79-ab84-4f6e-82cc-a896369d157c', 'Cartoon Channel PH', 'https://iyadtv.pages.dev/images/cartoon_channel_ph_47.png', 'https://live20.bozztv.com/giatv/giatv-cartoonchannelph/cartoonchannelph/chunks.m3u8', 'hls', NULL, NULL, 'general', true, 0, '2026-02-22 10:49:38.791851+00', '2026-04-08 02:50:00.122892+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('d2e4f05a-f5a8-4dd3-a408-b8f1bc7ff4d5', 'GNN', 'https://i.imgur.com/m6EFnqh.png', 'http://136.158.97.2:6610/001/2/ch00000090990000001234/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2Bp6sHVPy02nySMqUY2vMm%2BjytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001523&contentid=ch00000000000000001523&videoid=ch00000090990000001234&recommendtype=0&userid=1521078532205&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=EP8Z20BUC89XXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', NULL, NULL, 'general', true, 0, '2026-03-21 10:51:03.986282+00', '2026-04-08 02:50:31.75544+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, '["backup2","primary","backup","backup3","backup4","backup5","backup6"]', NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('b6a91293-7c28-4730-a7e9-71fa67cb047f', 'CGTN', 'https://static.wikia.nocookie.net/logopedia/images/2/24/CGTN_Documentary.svg/revision/latest/scale-to-width-down/250?cb=20210818141459', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cgtn/default/index.mpd', 'mpd', '0f854ee4412b11edb8780242ac120002', '9f2c82a74e727deadbda389e18798d55', 'news', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:50:05.29708+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('1cc9f4e7-7947-4cf2-8943-47ad91f5a0c0', 'TFC Asia', 'https://tse1.mm.bing.net/th/id/OIP.j_nk3c4VNogVe6T5_2LqBwHaEK?rs=1&pid=ImgDetMain&o=7&rm=3', 'https://cdn-ue1-prod.tsv2.amagi.tv/linear/amg01006-abs-cbn-tfcasia-dash-abscbnono/index.mpd', 'mpd', '9568cc84e1d944f38eac304517eab6fd', '2c8306892361e3fba18cb142f31ec775', 'general', true, 0, '2026-03-07 01:37:57.290053+00', '2026-04-08 02:51:34.201546+00', 'clearkey', NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('ba68529e-cc9a-4a48-98a7-e12088355f8c', 'Cartoon Network', 'https://i.imgur.com/9PLlajp.png', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/cartoonnetworkhd/default/index.mpd', 'mpd', 'a2d1f552ff9541558b3296b5a932136b', 'cdd48fa884dc0c3a3f85aeebca13d444', 'kids', true, 0, '2026-02-19 13:59:47.271426+00', '2026-05-17 11:49:14.179192+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('98fdb596-d4f9-4f18-bf56-8ed84f694510', 'AXN', 'https://upload.wikimedia.org/wikipedia/commons/d/d0/AXN_Logo_2015.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_axn_sd/default/index.mpd', 'mpd', '8a6c2f1e9d7b4c5aa1f04d2b7e9c1f88', '05e6bfa4b6805c46b772f35326b26b36', 'entertainment', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:49:49.478274+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('d6f30190-42b5-40e2-bb31-684341103523', 'TNT SPORTS 4 UK', 'https://i.ibb.co/52R1cbw/tnt4.png', 'https://otte.live.fly.ww.aiv-cdn.net/gru-nitro/live/dash/enc/pnu10tp36z/out/v1/912e9db56d75403b8a9ac0a719110f36/cenc.mpd', 'mpd', '192b1115da041585c77200128549efa1', '634e10efe4abbb14be400a3ccbac0258', 'general', true, 0, '2026-03-19 04:13:31.987658+00', '2026-04-08 02:51:40.148216+00', 'clearkey', NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('6718c9e7-cc35-4585-94e9-64d4134a4d7e', 'CNN INTERNATIONAL', 'https://th.bing.com/th/id/OIP.S7pJUpbQ6mU4KQeBF66nMgHaHa?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_cnnhd/default/index.mpd', 'mpd', '900c43f0e02742dd854148b7a75abbec', 'da315cca7f2902b4de23199718ed7e90', 'news', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:50:09.372103+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('02ba7b64-1ad2-4661-9334-535446d492dd', 'BBCWORLD News', 'https://th.bing.com/th/id/OIP.Dt6zbSEb8BztEMb1C93QHQHaHk?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/bbcworld_news_sd/default/index.mpd', 'mpd', 'f59650be475e4c34a844d4e2062f71f3', '119639e849ddee96c4cec2f2b6b09b40', 'news', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:49:51.759118+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('eefc3b3d-8c3a-4fcf-99d0-540c5a2ca1d8', 'Bloomberg', 'https://th.bing.com/th/id/OIP.ayx_C9FL75IKjIl408wLagHaFj?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/bloomberg_sd/default/index.mpd', 'mpd', '3b8e6d1f2c9a4f7d9a556c1e7b2d8f90', '09f0bd803966c4befbd239cfa75efe23', 'news', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:49:57.834734+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('c827c7f1-0d25-414d-a8d2-454c26a85816', 'CRIME INVESTIGATION', 'https://download.logo.wine/logo/Crime_%2B_Investigation_(Australian_TV_channel)/Crime_%2B_Investigation_(Australian_TV_channel)-Logo.wine.png', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/crime_invest/default/index.mpd', 'mpd', '21e2843b561c4248b8ea487986a16d33', 'db6bb638ccdfc1ad1a3e98d728486801', 'documentary', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:50:11.914639+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('027c4088-ef0e-416d-8d92-971cfcd7f2d5', 'Dreamworks HD', 'https://i.imgur.com/bzTr9Y2.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_dreamworks_hd1/default/index.mpd', 'mpd', '7b1e9c4d5a2f4d8c9f106d3a8b2c1e77', '8b2904224c6cee13d2d4e06c0a3b2887', 'kids', true, 0, '2026-02-19 14:01:30.092577+00', '2026-04-08 02:50:16.313604+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('35a2e358-4764-4b45-be57-27c692ec9771', 'Dreamworks Tagalog', 'https://i.imgur.com/bzTr9Y2.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_dreamworktag/default/index.mpd', 'mpd', '564b3b1c781043c19242c66e348699c5', 'd3ad27d7fe1f14fb1a2cd5688549fbab', 'kids', true, 0, '2026-02-19 14:01:30.092577+00', '2026-04-08 02:50:18.768451+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('35ab49ea-977a-4f78-ba6b-623849451e5f', 'Golden Television', 'https://imgur.com/9EGqMKY', 'https://goldentelevisionnetwork.sanmateocable.workers.dev/playlist.m3u8', 'hls', NULL, NULL, 'general', false, 0, '2026-03-14 13:58:57.769634+00', '2026-04-08 02:50:32.424702+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'offline', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('f2d212d9-5028-4423-9ac0-1aebf572992a', 'HBO ZONE', 'https://static.wikia.nocookie.net/dreamlogos/images/6/67/HBO_Zone_1996.png/revision/latest/scale-to-width-down/260?cb=20191031133037', 'https://thetvapp.to/tv/espn-live-stream/', 'hls', NULL, NULL, 'general', true, 0, '2026-03-12 10:52:41.861608+00', '2026-04-08 02:50:36.241138+00', NULL, NULL, NULL, false, NULL, NULL, 'HBOZoneEast', 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('330b4418-ad35-44bd-a0cf-97dd561c390d', 'Cinemax', 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTFgovJL0c5CV8hntZiJ9YiHRF2kbssZQVCAQ&s', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_cinemax/default/index.mpd', 'mpd', 'b207c44332844523a3a3b0469e5652d7', 'fe71aea346db08f8c6fbf0592209f955', 'Movies', true, 0, '2026-02-19 13:59:47.271426+00', '2026-05-13 11:53:42.744516+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('ccfa5dbc-bb4b-44b6-950a-fdd316c16719', 'Channel News Asia', 'https://www.sopasia.com/wp-content/uploads/2014/04/logo_Channel-NewsAsia-logo.jpg', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/channelnewsasia/default/index.mpd', 'mpd', 'b259df9987364dd3b778aa5d42cb9acd', '753e3dba96ab467e468269e7e33fb813', 'news', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:50:05.224512+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('c0f4e83d-eb09-4e3d-802c-ef658c54cde2', 'CinemaOne', 'https://static.wikia.nocookie.net/russel/images/9/94/Cinema_One_Logo_2020.png', 'https://abslive.akamaized.net/dash/live/2027618/c1ph/manifest.mpd', 'mpd', '55eddd1e157e4c3b830866e4679e7032', '525030e984567ba8df0af80660952368', 'movies', true, 0, '2026-02-19 13:59:47.271426+00', '2026-05-15 00:45:04.45968+00', 'clearkey', 'https://ottmdrm.comclark.com/widevine/', NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('3c27832b-b200-489d-a25d-4e557c7ff458', 'Global Trekker', 'https://cdn2.ettoday.net/images/6892/e6892888.jpg', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/globaltrekker/default/index.mpd', 'mpd', 'b7a6c5d23f1e4a9d8c721e5d9f4a6b13', '63ca9ad0d88fccb8c667b028f47287ba', 'documentary', true, 0, '2026-02-19 14:01:30.092577+00', '2026-04-08 02:50:27.728056+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('369335c2-3bd3-4f4d-9ea6-4d165f3e2028', 'HBO Family', 'https://divign0fdw3sv.cloudfront.net/Images/ChannelLogo/contenthub/450_144.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_hbofam/default/index.mpd', 'mpd', '872910c843294319800d85f9a0940607', 'f79fd895b79c590708cf5e8b5c6263be', 'movies', true, 0, '2026-02-19 14:01:30.092577+00', '2026-04-08 02:50:34.341937+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('34acb264-958d-497f-b2dd-f6c0874685de', 'HBO Hits', 'https://vignette.wikia.nocookie.net/logopedia/images/0/04/HBO_HiTS.svg/revision/latest/scale-to-width-down/627?cb=20100511073403', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_hbohits/default/index.mpd', 'mpd', 'b04ae8017b5b4601a5a0c9060f6d5b7d', 'a8795f3bdb8a4778b7e888ee484cc7a1', 'Movies', true, 0, '2026-02-19 14:01:30.092577+00', '2026-04-08 02:50:36.343374+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('cb89d39c-bb66-4bc7-a9bd-85bd7e6001c8', 'HGTV HD', 'https://upload.wikimedia.org/wikipedia/commons/0/05/HGTV_logo.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/hgtv_hd1/default/index.mpd', 'mpd', 'f1e8c2d97a3b4f5d8c669d1a2b7e4c30', '03aaa7dcf893e6b934aeb3c46f9df5b9', 'entertainment', true, 0, '2026-02-19 14:01:30.092577+00', '2026-04-08 02:50:38.347107+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('17fdafe7-7e8e-424d-91fb-64808a84de6f', 'Hits HD', 'https://th.bing.com/th/id/OIP.x2dQgh_yGBdnttScluIGYAHaCp?w=900&h=322&rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/hits_hd1/default/index.mpd', 'mpd', '6d2f8a1c9b5e4c7da1f03e7b9d6c2a55', '37c9835795779f8d848a6119d3270c69', 'movies', true, 0, '2026-02-19 14:03:15.902679+00', '2026-04-08 02:50:42.333912+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('7c872f0d-5be9-48ee-a33a-add609f5ac76', 'History HD', 'https://th.bing.com/th/id/OIP.Yx9hYOFfO03taYL2CZd6FAHaE8?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/dr_historyhd/default/index.mpd', 'mpd', 'e2a8c7d15b9f4d6a9c101f7e3b2d8a44', '397ca914a73b1e00bc94ed9eccf9c258', 'documentary', true, 0, '2026-02-19 14:01:30.092577+00', '2026-04-08 02:50:42.383539+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('c8b64ea3-d627-4b13-bf47-2c6a44f2ed82', 'Hits Now', 'https://th.bing.com/th/id/OIP.cM1HO2isouoNessbj31CcgAAAA?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_hitsnow/default/index.mpd', 'mpd', 'f9c3d6b18a2e4d7f9e453b1a8c6d2f70', 'ce8874347ec428c624558dcdc3575dd4', 'movies', true, 0, '2026-02-19 14:03:15.902679+00', '2026-04-08 02:50:44.336878+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('8b8adac8-f3e8-40a6-89aa-d47387d280d6', 'KBS World', 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRjrxyZu1bPiJ3SdGvhVf3d3Muj5AqQ7ZkGpw&s', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/kbsworld/default/index.mpd', 'mpd', '22ff2347107e4871aa423bea9c2bd363', 'c6e7ba2f48b3a3b8269e8bc360e60404', 'entertainment', true, 0, '2026-02-19 14:03:15.902679+00', '2026-04-08 02:50:54.084544+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('6dc73b58-ef9c-4e02-89a8-019fce27cb0e', 'Knowledge Channel', 'https://th.bing.com/th/id/OIP.ix5ReWijxZg8uPcKrk2GHwHaGd?rs=1&pid=ImgDetMain', 'https://abslive.akamaized.net/dash/live/2027618/kc/manifest.mpd', 'mpd', 'bd1f88dd3b254514bf7a113188c10dc2', 'ea86da60f0116f3b92a86acf45b8e071', 'education', true, 0, '2026-02-19 14:03:15.902679+00', '2026-04-08 02:50:56.949127+00', 'clearkey', NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('24185b67-6800-4ce3-99db-6261edde29c0', 'Lotus Macau', 'https://i.imgur.com/5G72qjx.png', 'http://136.239.159.20:6610/001/2/ch00000090990000001196/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2BrUraXHxRLZkchi69sJ%2B10xytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001400&contentid=ch00000000000000001400&videoid=ch00000090990000001196&recommendtype=0&userid=1065444060343&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=9JQRNS5OZKWXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', '9a7c2d1f4e8b4a6d8f301b5c9e7d2a44', 'ca88469cabc18aa33d1f2e46a6efb4f7', 'entertainment', true, 0, '2026-02-19 14:03:15.902679+00', '2026-04-08 02:50:58.599048+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('15dad54f-ef39-4cd7-a130-e19fcfcbb3b0', 'NHK JAPAN', 'https://logowik.com/content/uploads/images/nhk-world-japan1495.jpg', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/dr_nhk_japan/default/index.mpd', 'mpd', '3d6e9d4de7d7449aadd846b7a684e564', '0800fff80980f47f7ac6bc60b361b0cf', 'news', true, 0, '2026-02-19 14:03:15.902679+00', '2026-04-08 02:51:04.810146+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('ae333a56-e5e3-4f6f-aae9-75b160fd6629', 'Lifetime', 'https://i.imgur.com/Qvj8mf4.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/dr_lifetime/default/index.mpd', 'mpd', 'cf861d26e7834166807c324d57df5119', '64a81e30f6e5b7547e3516bbf8c647d0', 'entertainment', true, 0, '2026-02-19 14:03:15.902679+00', '2026-04-08 02:50:56.933588+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('1b16862b-a621-4b4c-a6b7-84847ed272a6', 'NBA TV Philippines', 'https://cms.cignal.tv/Upload/Images/NBA-TV-Philippines.jpg', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cgnl_nba/default/index.mpd', 'mpd', 'd1f8a0c97b3d4e529a6f2c4b8d7e1f90', '58ab331d14b66bf31aca4284e0a3e536', 'Sports', true, 0, '2026-02-19 14:03:15.902679+00', '2026-04-08 02:51:04.91515+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('fc9001eb-cfb7-4419-a019-718c273ac196', 'Discovery Channel', 'https://th.bing.com/th/id/OIP.4ONCH8mk4foZNv6W4xM0nQHaGa?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/discovery/default/index.mpd', 'mpd', 'd9ac48f5131641a789328257e778ad3a', 'b6e67c37239901980c6e37e0607ceee6', 'documentary', true, 0, '2026-02-19 14:01:30.092577+00', '2026-04-08 02:50:14.012282+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('f5b00122-7f26-4d22-bcbc-f92dd7f48b57', 'One PH', 'https://i.imgur.com/gkluDe9.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/oneph_sd/default/index.mpd', 'mpd', 'b1c7e9d24f8a4d6c9e337a2f1c5b8d60', '8ff2e524cc1e028f2a4d4925e860c796', 'entertainment', true, 0, '2026-02-19 14:04:59.209157+00', '2026-04-08 02:51:09.234213+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('b4f84fbf-1715-4715-848a-3e1a37d3aab1', 'One Sports Plus HD', 'https://yt3.ggpht.com/a/AATXAJxL2nOhPRXCDKBEK-ccmTRM0G5r24tnVWUraw=s900-c-k-c0xffffffff-no-rj-mo', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/cg_onesportsplus_hd1/default/index.mpd', 'mpd', 'f00bd0122a8a4da1a49ea6c49f7098ad', 'a4079f3667ba4c2bcfdeb13e45a6e9c6', 'Sports', true, 0, '2026-02-19 14:04:59.209157+00', '2026-04-08 02:51:11.604894+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('62bf8189-952b-47cc-a48b-54b57d63f5a5', 'HBO HD', 'https://th.bing.com/th/id/OIP.lY5V2M3D9jtBFJNbOAI8swHaDt?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_hbohd/default/index.mpd', 'mpd', 'c2b7a1e95d4f4c3a8e617f9d0a2b6c18', '27fca1ab042998b0c2f058b0764d7ed4', 'Movies', true, 0, '2026-02-19 14:01:30.092577+00', '2026-04-08 02:50:34.332634+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('d98423dd-c677-43ab-91fb-deab4cdeabbe', 'Nickelodeon', 'http://apkip.tv/logos/UK/Nickelodeon.uk.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/dr_nickelodeon/default/index.mpd', 'mpd', '9ce58f37576b416381b6514a809bfd8b', 'f0fbb758cdeeaddfa3eae538856b4d72', 'kids', true, 0, '2026-02-19 14:04:59.209157+00', '2026-05-17 09:16:17.525257+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('8e72c8f7-1708-42da-983c-628176693bd9', 'UAAP Varsity', 'https://i.imgur.com/pt2hGDc.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_uaap_cplay_sd/default/index.mpd', 'mpd', '95588338ee37423e99358a6d431324b9', '6e0f50a12f36599a55073868f814e81e', 'sports', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:52.424862+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('d6ae8554-4c69-4012-b842-6bdbae287283', 'Kapatid', 'https://tse4.mm.bing.net/th/id/OIP.8mRrpNIEyAIflHdDbDUgqQHaEK?rs=1&pid=ImgDetMain&o=7&rm=3', 'https://ucdn.mediaquest.com.ph/bpk-tv/kapatid_hd/default/index.mpd', 'mpd', '045d103180f64562b1db7c932741c3ba', 'c3380548b9075c767a6ae2006ef4bff8', 'entertainment', true, 0, '2026-02-19 14:03:15.902679+00', '2026-04-08 10:31:19.039321+00', 'clearkey', NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'offline', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('a543c0d4-67f1-47c6-b91d-dbe607e0124e', 'Abante Radyo', 'https://www.allonlineradio.com/wp-content/uploads/2025/03/Philippines-radio-Abante-Radyo-Tabloidista-logo.jpg', 'https://amg19223-amg19223c12-amgplt0352.playout.now3.amagi.tv/playlist/amg19223-amg19223c12-amgplt0352/playlist.m3u8', 'hls', NULL, NULL, 'general', true, 0, '2026-03-20 03:03:36.486365+00', '2026-04-08 02:49:38.226491+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('e7772c51-a40b-4dff-801b-ff51a88062a5', 'Detective conan', 'https://disney.images.edge.bamgrid.com/ripcut-delivery/v2/variant/disney/9faacefd-8497-420d-a8b2-1c49d1b43dc8/compose?format=webp&width=2560', 'https://www.youtube.com/embed/live_stream?channel=UCLPx-wHTCA-1szpeN3OS85A', 'youtube', NULL, NULL, 'general', true, 0, '2026-04-01 04:33:34.942828+00', '2026-04-08 02:50:11.801116+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('ce17a5b2-da84-43b4-95f7-d4298c5b1b09', 'Food Network HD', 'https://upload.wikimedia.org/wikipedia/commons/f/f9/Food_Network_New_Logo.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_foodnetwork_hd1/default/index.mpd', 'mpd', '4a9d2f7c1e6b4c8d8a55d7b1e3f0c926', '2e62531bdb450480a18197b14f4ebc77', 'entertainment', true, 0, '2026-02-19 14:01:30.092577+00', '2026-04-08 02:50:25.761048+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('7c0cea47-78ec-41a2-81c2-af58ab4fc3a4', 'PTV4', 'https://media.philstar.com/images/articles/ptv4_2018-06-14_11-27-10.jpg', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/cg_ptv4_sd/default/index.mpd', 'mpd', '71a130a851b9484bb47141c8966fb4a3', 'ad1f003b4f0b31b75ea4593844435600', 'news', true, 0, '2026-02-19 14:04:59.209157+00', '2026-04-08 02:51:15.788184+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('fb45e1c6-46a6-43fc-8f29-625919572eb4', 'SPOTV', 'https://linear-poster.astro.com.my/prod/logo/SPOTV.png', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/cg_spotvhd/default/index.mpd', 'mpd', 'ec7ee27d83764e4b845c48cca31c8eef', '9c0e4191203fccb0fde34ee29999129e', 'sports', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:25.919455+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('ab248eab-ae04-448c-a091-bd5f2d2b973a', 'Rock Action', 'https://th.bing.com/th/id/OIP.0c6d3hoH5evqsJVNnbhVNwHaC3?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/depedch_sd/default/index.mpd', 'mpd', '0f853706412b11edb8780242ac120002', '2157d6529d80a760f60a8b5350dbc4df', 'movies', true, 0, '2026-02-19 14:04:59.209157+00', '2026-05-14 06:12:08.987941+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('eb46abb8-1d87-48a8-ab38-e14875f50953', 'TV5', 'https://cms.cignal.tv/Upload/Thumbnails/TV5%20HD%20logo%20(1).png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/tv5_hd/default1/index.mpd', 'mpd', '2615129ef2c846a9bbd43a641c7303ef', '07c7f996b1734ea288641a68e1cfdc4d', 'entertainment', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:48.42571+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('f5aadd89-ba11-4bbe-8a82-ba1fdd6bead3', 'MTV', 'https://logos-world.net/wp-content/uploads/2020/09/MTV-Logo.png', 'https://thetvapp.to/tv/espn-live-stream/', 'hls', NULL, NULL, 'general', true, 0, '2026-03-12 10:54:17.015284+00', '2026-04-08 02:51:02.606748+00', NULL, NULL, NULL, false, NULL, NULL, 'MTVEast', 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('176b4ef7-e1c5-4c2a-8192-616c87926f61', 'TVN', 'https://i.imgur.com/3zLgtdM.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_tvnpre/default/index.mpd', 'mpd', 'e1bde543e8a140b38d3f84ace746553e', 'b712c4ec307300043333a6899a402c10', 'entertainment', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:50.481213+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('4735a9d4-8724-421d-8205-c915e6c2fe0e', 'VIVA', 'https://i.imgur.com/z8lWIX6.png', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/viva_sd/default/index.mpd', 'mpd', '07aa813bf2c147748046edd930f7736e', '3bd6688b8b44e96201e753224adfc8fb', 'Movies', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:54.487543+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('5adf580a-14ff-43d7-b282-b4b2c1227f49', 'PBO', 'https://i.imgur.com/ZUZIt9s.png', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/pbo_sd/default/index.mpd', 'mpd', 'dcbdaaa6662d4188bdf97f9f0ca5e830', '31e752b441bd2972f2b98a4b1bc1c7a1', 'Movies', true, 0, '2026-02-19 14:04:59.209157+00', '2026-04-08 02:51:13.602204+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('d5d81210-0026-4d75-ae30-3a579b1bd61c', 'Premier Sports', 'https://th.bing.com/th/id/OIP.UEZdJevwcZaL1qmePWjLGgHaHY?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_ps_hd1/default/index.mpd', 'mpd', 'b8b595299fdf41c1a3481fddeb0b55e4', 'cd2b4ad0eb286239a4a022e6ca5fd007', 'sports', true, 0, '2026-02-19 14:04:59.209157+00', '2026-04-08 02:51:15.723028+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('74df2a65-e359-4bcb-b385-9ec15dddf417', 'Premier Tennis', 'https://th.bing.com/th/id/OIP.yd4QRZWcEgEz2T1EZv41mAAAAA?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/premiersports2hd/default/index.mpd', 'mpd', '59454adb530b4e0784eae62735f9d850', '61100d0b8c4dd13e4eb8b4851ba192cc', 'sports', true, 0, '2026-02-19 14:04:59.209157+00', '2026-04-08 02:51:15.72875+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('6d314d80-850b-44fd-ab13-e899025d253f', 'SARISARI', 'https://vignette1.wikia.nocookie.net/logopedia/images/3/3e/Sari-Sari_alternate_Logo.PNG/revision/latest?cb=20160619031101', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_sarisari/default/index.mpd', 'mpd', '0a7ab3612f434335aa6e895016d8cd2d', 'b21654621230ae21714a5cab52daeb9d', 'entertainment', true, 0, '2026-02-19 14:04:59.209157+00', '2026-04-08 02:51:21.761433+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('5684781c-d56a-4e15-be81-f9d44048f333', 'Tap Movies', 'https://cms.cignal.tv/Upload/Images/Tap-movies.jpg', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_tapmovies_hd1/default/index.mpd', 'mpd', '71cbdf02b595468bb77398222e1ade09', 'c3f2aa420b8908ab8761571c01899460', 'movies', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:30.076894+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('f38733cf-6a10-4339-a822-2116d7066e52', 'True FM TV', 'https://th.bing.com/th/id/OIP.mnFsqTyoPfS65QqSTLKHLAHaHa?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/truefm_tv/default/index.mpd', 'mpd', 'a4e2b9d61c754f3a8d109b6c2f1e7a55', '1d8d975f0bc2ed90eda138bd31f173f4', 'music', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:42.268708+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('d8dd5cdd-eeb6-47c0-abb7-dc12054b0788', 'TVN Movies (Tagalog)', 'https://i.imgur.com/3zLgtdM.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_tvnmovie/default/index.mpd', 'mpd', '2e53f8d8a5e94bca8f9a1e16ce67df33', '3471b2464b5c7b033a03bb8307d9fa35', 'movies', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:50.540376+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('0c3fe151-bfeb-4cdb-abb5-ba02901b7f8e', 'Asian Food Network', 'https://tse2.mm.bing.net/th/id/OIP.pgsV2DrWEXjdLRiouadQTwHaFj?w=800&h=600&rs=1&pid=ImgDetMain&o=7&rm=3', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/asianfoodnetwork_sd/default/index.mpd', 'mpd', '1619db30b9ed42019abb760a0a3b5e7f', '5921e47fb290ae263291b851c0b4b6e4', 'general', true, 0, '2026-02-20 10:08:32.376579+00', '2026-04-08 02:49:49.745919+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('43b070fc-be04-4978-ae1d-08377ae029a3', 'Bein Sports 1', 'https://upload.wikimedia.org/wikipedia/commons/e/e5/Logo_bein_sports_1.png', 'https://unifi-live2.secureswiftcontent.com/Content/DASH/Live/channel(bein1)/manifest.mpd', 'mpd', 'd48b6088253c443eb94d27cb7828f707', 'e9776141f9e949273a072b0e035070ab', 'general', true, 0, '2026-03-19 10:29:23.300014+00', '2026-05-16 23:09:58.245676+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'vercel', 'VPN REQUIRED!', 'Kailangan ng VPN (Singapore) Para mag play', 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('74efa7c5-34d0-4ca3-8309-f61b94110fef', 'TSN4', 'https://r2.thesportsdb.com/images/media/channel/fanart/9wma511726868598.jpg', 'https://iwanttfc.mikuy30.dpdns.org/gmapinoytv.mpd', 'hls', NULL, NULL, 'general', false, 0, '2026-03-22 09:58:12.282674+00', '2026-04-08 02:51:45.444972+00', NULL, NULL, NULL, false, NULL, NULL, 'tsn4', 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('d21527b3-192b-4fb2-adf1-e98f79491b94', 'TSN5', 'https://r2.thesportsdb.com/images/media/channel/fanart/9wma511726868598.jpg', 'https://wmjebiejrjgfafsniqlx.supabase.co/functions/v1/stream-proxy?url=http://trilo.tv/live/Eden1/123456789/368076.m3u8', 'hls', NULL, NULL, 'general', false, 0, '2026-03-22 09:58:41.128028+00', '2026-04-08 02:51:45.969135+00', NULL, NULL, NULL, false, NULL, NULL, 'tsn5', 'none', NULL, NULL, 'offline', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('109425b9-3f88-4276-9bb4-2aa2bdca94ac', 'MeTV Toons', 'https://wpcdn.us-east-1.vip.tn-cloud.net/www.abccolumbia.com/content/uploads/2024/06/t/v/metv-toons-logo-gold.png', 'https://iwanttfc.mikuy30.dpdns.org/gmapinoytv.mpd', 'hls', NULL, NULL, 'general', true, 0, '2026-03-22 10:07:33.424463+00', '2026-04-08 02:51:00.613371+00', NULL, NULL, NULL, false, NULL, NULL, 'metv-toons', 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('3c84656b-da63-4c58-9b9e-9a05b8283a69', 'BBC Earth', 'https://i.imgur.com/cvYi2Io.png', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/cg_bbcearth_hd1/default/index.mpd', 'mpd', '34ce95b60c424e169619816c5181aded', '0e2a2117d705613542618f58bf26fc8e', 'documentary', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:49:51.660918+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('a7774de7-d828-4ba0-bdea-d00ad2286767', 'Nicktoons', 'https://blogger.googleusercontent.com/img/b/R29vZ2xl/AVvXsEja0yJ4sqj3s2pOdMI-A5IZjYE_cuUN36kZKCvICzO6SDIX7Wz4qbShs3ADSomFu192Ji_zLGCpxG_AX-Zdyau3iPuOy0LEbje1VweLr790tRqkqU49sHhe2kfYE_RR92EyMLi88PYqcBA5AQVA0Avha2-Oa-Z70DGH7732pKVKkyqPM6tZahD6/s1920/nicktoons-logo-2023-rebrand_2.png', 'https://iwanttfc.mikuy30.dpdns.org/gmapinoytv.mpd', 'hls', NULL, NULL, 'general', true, 0, '2026-03-22 10:10:47.073015+00', '2026-04-08 02:51:06.660427+00', NULL, NULL, NULL, false, NULL, NULL, 'NicktoonsEast', 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('23d0b65d-1dea-4861-b038-874613d73faf', 'Animax HD ', 'https://i.imgur.com/VLlyHhT.png', 'https://amg02159-amg02159c9-amgplt0352.playout.now3.amagi.tv/ts-eu-w1-n2/playlist/amg02159-amg02159c9-amgplt0352/playlist.m3u8', 'hls', '4bd30e54571144eb9168a1a7e5915f75', 'f8cb24e54d555381a326c157b5dfaa59', 'general', true, 0, '2026-03-19 11:24:35.104566+00', '2026-05-15 10:41:20.597772+00', NULL, NULL, NULL, true, NULL, '["backup6","primary","backup","backup2","backup3","backup4","backup5"]', NULL, 'cloudflare', 'VPN REQUIRED!', 'Kailangan ng VPN (Singapore) Para mag play', 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('cb102b0e-c43c-4a1f-be05-729cf2159b10', 'Bilyonaryo', 'https://th.bing.com/th/id/OIP.O2OG_59US0j-zqWyZwqhXAHaCH?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/bilyonaryoch/default/index.mpd', 'mpd', '227ffaf09bec4a889e0e0988704d52a2', 'b2d0dce5c486891997c1c92ddaca2cd2', 'news', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:49:55.611519+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('eca4c757-e72b-4a51-8e47-5307caa4bc9f', 'One News HD', 'https://th.bing.com/th/id/OIP.x5VzEESkd4_1pVGulNU43gHaGN?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/onenews_hd1/default/index.mpd', 'mpd', '2e6a9d7c1f4b4c8a8d33c7b1f0a5e924', '4c71e178d090332fbfe72e023b59f6d2', 'news', true, 0, '2026-02-19 14:04:59.209157+00', '2026-04-08 02:51:09.198175+00', 'clearkey', NULL, NULL, true, NULL, '["backup","primary","backup2","backup3","backup4","backup5","backup6"]', NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('3321ec3a-e656-4040-bc34-bfcd0e33d42c', 'UNTV', 'https://static.wikia.nocookie.net/dxs/images/c/c3/UNTV_Public_Service_Logo_2022.png/revision/latest?cb=20221014202457', 'http://136.239.173.10:6610/001/2/ch00000090990000001091/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2Bp8EKxpteUJNLDuI18c3YYNytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001177&contentid=ch00000000000000001177&videoid=ch00000090990000001091&recommendtype=0&userid=1785051491883&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=7BZSNFMO8LPXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', NULL, NULL, 'general', true, 0, '2026-03-08 10:18:57.097064+00', '2026-04-08 02:51:52.089686+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('6dbbde8f-5ba2-42ec-a8eb-2ebea1d58d1e', 'Outdoor Channel', 'https://mir-s3-cdn-cf.behance.net/project_modules/max_1200/57409e50258033.58cb840c2bbbb.jpg', 'https://thetvapp.to/tv/espn-live-stream/', 'hls', NULL, NULL, 'general', true, 0, '2026-03-12 11:05:35.063918+00', '2026-04-08 02:51:11.53006+00', NULL, NULL, NULL, false, NULL, NULL, 'OutdoorChannel', 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('2d7474ad-c223-4d19-a307-2b1ecb154fb2', 'Comic U', NULL, 'https://amg19223-amg19223c8-amgplt0351.playout.now3.amagi.tv/playlist/amg19223-amg19223c8-amgplt0351/playlist.m3u8', 'hls', NULL, NULL, 'general', true, 0, '2026-03-20 03:04:23.426522+00', '2026-04-08 02:50:09.996665+00', NULL, NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('6256459b-c272-4e78-9538-c069554e9255', 'Pinoy Xtreme', 'https://cms.cignal.tv/Upload/Thumbnails/Oiniy-Extreme.png', 'http://136.239.158.18:6610/001/2/ch00000090990000001098/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20TsXah2%2FZLFNNIdWrVrXDMApC219uqwL0dVmslrkAjamFsyK4TH4mOENKJ45mwOyS0g%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001222&contentid=ch00000000000000001222&videoid=ch00000090990000001098&recommendtype=0&userid=1869817604648&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=NKXBKKPYOEXXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO&IASHttpSessionId=RR20448020260101155237185089&ispcode=55', 'mpd', NULL, NULL, 'general', true, 0, '2026-03-19 05:00:57.737624+00', '2026-04-08 02:51:13.193336+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('1d2a5c7f-7836-4a90-b623-ac50b4c47b73', 'Al Jazeera', 'https://pluspng.com/img-png/al-jazeera-logo-png-al-jazeera-channel-png-pluspng-com-al-jazeera-television-png-268.png', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/dr_aljazeera/default/index.mpd', 'mpd', '7f3d900a04d84492b31fe9f79ac614e3', 'd33ff14f50beac42969385583294b8f2', 'general', true, 0, '2026-03-13 10:22:22.997316+00', '2026-04-08 02:49:40.331141+00', 'clearkey', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('8cff9bc9-f838-4738-8aae-207193e104da', 'Heart Of Asia', 'https://static.wikia.nocookie.net/dxs/images/b/b0/Heart_of_Asia_2D_Logo_2020.png/revision/latest?cb=20221015110217', 'https://hls.nathcreqtives.com/playlist.m3u8?id=1&token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJXZXNsZXkiLCJpYXQiOjE3NzQ2NjYxMDYsImV4cCI6MTgwMjk1ODQwMywiYWNjb3VudEV4cGlyZWQiOmZhbHNlLCJhY2NvdW50RXhwaXJlc0F0IjoxODAyOTU4NDAzLCJhbGxvd2VkT3JpZ2lucyI6WyJodHRwczovL2hvbWUubmF0aGNyZXF0aXZlcy5jb20iXX0.8_9sRDpADeWb82nTw7ydJ6UhqtXxMxGD0n88NWeUxZU', 'hls', NULL, NULL, 'general', false, 0, '2026-03-31 10:33:39.797237+00', '2026-04-08 02:50:39.00681+00', NULL, NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'offline', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('0c3b85c2-bf4f-4a22-b2df-524997630537', 'Cartoonito', 'https://i.imgur.com/x1wehbs.png', 'http://161.49.17.2:6610/001/2/ch00000090990000001125/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2BoZQDeIq8A03ROpfeWN75MYytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001238&contentid=ch00000000000000001238&videoid=ch00000090990000001125&recommendtype=0&userid=1642489849443&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=9X3U5ZPDLQVXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', NULL, NULL, 'general', true, 0, '2026-03-21 10:48:17.45705+00', '2026-04-08 02:50:03.02669+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, '["backup2","primary","backup","backup3","backup4","backup5","backup6"]', NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('0813ff0e-200b-47e5-b60a-0b3d0fdfdbe7', 'Celestial Movies Pinoy', 'https://cms.cignal.tv/Upload/Images/Celestial-Logo-2022.jpg', 'http://136.239.159.20:6610/001/2/ch00000090990000001077/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2BrHUpvQtyXgWxpVCozt4hcgytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001136&contentid=ch00000000000000001136&videoid=ch00000090990000001077&recommendtype=0&userid=1863800460286&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=EJ21Z5961VKXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', '0f8537d8412b11edb8780242ac120002', '2ffd7230416150fd5196fd7ea71c36f3', 'movies', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:50:04.83468+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('d57b15a8-4991-4346-8fe6-b9baff7abff4', 'Kix HD', 'https://i.imgur.com/B8Fmzer.png', 'http://136.239.159.20:6610/001/2/ch00000090990000001263/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2BqszdaNqmegxz2VkIuTd%2B31ytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001583&contentid=ch00000000000000001583&videoid=ch00000090990000001263&recommendtype=0&userid=1319115127597&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=D4NMMH3RZQXXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', 'c9d4b7a18e2f4d6c9a103f5b7e1c2d88', '7f3139092bf87d8aa51ee40e6294d376', 'entertainment', true, 0, '2026-02-19 14:03:15.902679+00', '2026-04-08 02:50:53.733963+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('fa8b1514-097e-4e35-87bc-321027e8835c', 'Warner TV', 'https://th.bing.com/th/id/OIP.8xIdcYektX82pKAdaXcQEgHaHr?rs=1&pid=ImgDetMain', 'http://136.239.158.18:6610/001/2/ch00000090990000001096/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2BqRhIO4pq%2FZNG%2BJhjsEpHHCytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001219&contentid=ch00000000000000001219&videoid=ch00000090990000001096&recommendtype=0&userid=1321207134399&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=0QVRZ4LBHCCXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', '7f2a9c6d1e5b4c8a8d10a2b7e1c9f344', 'ae3d135d5ddd9e8f3a7bbfbfae0e40d1', 'entertainment', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:54.002023+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('77fd24de-64c2-47c3-b069-221ca9d0ffba', 'A2Z', 'https://i.imgur.com/pRwyOMP.png', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/cg_a2z/default/index.mpd', 'mpd', '3f6d8a2c1b7e4c9f8d52a7e1b0c6f93d', '4019f9269b9054a2b9e257b114ebbaf2', 'entertainment', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:49:37.690756+00', 'clearkey', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('f910e3fa-21ef-45cd-9fb0-6ed3898efa31', 'TAP Sports', 'https://i.imgur.com/ZsWDiRF.png', 'http://136.239.173.3:6610/001/2/ch00000090990000001151/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2BqvuCQC%2BfGfSFGYE2TZKWpbytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001321&contentid=ch00000000000000001321&videoid=ch00000090990000001151&recommendtype=0&userid=1148739009053&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=Z6EHYVCYR3XXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', '5e7c1b9a2d8f4a6c9f30b1d6e2a8c744', '6178d9d177689eec5028e2dd608ae7b6', 'sports', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:29.607332+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('750dd0a0-ae70-4de8-a607-91a1b3ef8acb', 'SPOTV2', 'https://cms.dmpcdn.com/livetv/2023/02/06/00d2eb00-a5c0-11ed-a358-099f80363291_webp_original.png', 'https://qp-pldt-live-bpk-01-prod.akamaized.net/bpk-tv/dr_spotv2hd/default/index.mpd', 'mpd', '7eea72d6075245a99ee3255603d58853', '6848ef60575579bf4d415db1032153ed', 'sports', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:26.085951+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('817dcce5-4361-4d69-b722-bcd53c46eb98', 'Tap Edge', 'https://static.wikia.nocookie.net/logopedia/images/7/77/TAP_Edge_logo.png/revision/latest?cb=20210901164231', 'https://converse.nathcreqtives.com/1150/manifest.mpd?token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJXZXNsZXkiLCJpYXQiOjE3NzQ2NjYxMDYsImV4cCI6MTgwMjk1ODQwMywiYWNjb3VudEV4cGlyZWQiOmZhbHNlLCJhY2NvdW50RXhwaXJlc0F0IjoxODAyOTU4NDAzLCJhbGxvd2VkT3JpZ2lucyI6WyJodHRwczovL2hvbWUubmF0aGNyZXF0aXZlcy5jb20iXX0.8_9sRDpADeWb82nTw7ydJ6UhqtXxMxGD0n88NWeUxZU', 'mpd', 31363232353337323935353433383639, '696d305237483130677335756d643933', 'general', true, 0, '2026-03-31 01:14:13.177135+00', '2026-04-08 02:51:30.110044+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('7148d52c-7df0-4109-bc7e-83a358fdfb6f', 'Aliw Channel', 'https://static.wikia.nocookie.net/logopedia/images/3/34/ABCLogo.png/revision/latest?cb=20161012105022', 'http://136.239.173.3:6610/001/2/ch00000090990000001109/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2Bp%2BWYKp0pXQLOnfpLMLHi2tytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001234&contentid=ch00000000000000001234&videoid=ch00000090990000001109&recommendtype=0&userid=1657667082928&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=JK9HJ5J3VGXXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', NULL, NULL, 'general', true, 0, '2026-03-09 10:13:31.368043+00', '2026-05-15 10:44:42.541952+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('779d2440-860e-4e4b-a0db-a278aa72b96a', 'TAP TV', 'https://th.bing.com/th/id/OIP.6ypmkyHr4CsiHriWt327pgHaHc?rs=1&pid=ImgDetMain', 'http://136.239.158.30:6610/001/2/ch00000090990000001149/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2BroVo9XMLpd0k2y9rVerSvmytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001319&contentid=ch00000000000000001319&videoid=ch00000090990000001149&recommendtype=0&userid=1260399616449&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=RY6345WC6DSXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', '5c1e7b9d2f6a4d8c8a55e9d2c7b1a344', 'e72d21a22e89660ff0ec33627eb4ef35', 'entertainment', true, 0, '2026-02-19 14:06:16.730317+00', '2026-04-08 02:51:31.680851+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('8011675c-8356-4679-80bd-e3474ea83025', 'RJTV', 'https://static.wikia.nocookie.net/logopedia/images/5/59/Screenshot_2019-08-30_at_5.25.09_PM.png', 'http://136.239.158.10:6610/001/2/ch00000090990000001159/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2BreKmZs4H3Zuj6jrvRtgmFqytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001395&contentid=ch00000000000000001395&videoid=ch00000090990000001159&recommendtype=0&userid=1981697457601&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=VPNC8TXZ55DXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', NULL, NULL, 'general', true, 0, '2026-03-12 01:30:04.910531+00', '2026-04-08 02:51:17.306168+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('bc2a97a9-2a01-49c8-9f66-3415012d0638', 'ANC', 'https://vignette.wikia.nocookie.net/russel/images/5/52/ANC_HD_Logo_2016.png/revision/latest?cb=20180404015018', 'https://cdn-ue1-prod.tsv2.amagi.tv/linear/amg01006-abs-cbn-anc-global-dash-abscbnono/index.mpd', 'mpd', '4bbdc78024a54662854b412d01fafa16', '8c6c920cf3f7df2087b0ae1a4a8c6058', 'news', true, 0, '2026-02-19 13:59:47.271426+00', '2026-05-15 01:18:42.678159+00', 'clearkey', 'https://ottmdrm.comclark.com/widevine/', NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('3cf4c259-2931-4ee5-92dc-4939099bbf2b', '&', NULL, 'https://unifi-live2.secureswiftcontent.com/Content/DASH/Live/channel(animax)/manifest.mpd', 'hls', '4bd30e54571144eb9168a1a7e5915f75', 'f8cb24e54d555381a326c157b5dfaa59', 'movies', false, 0, '2026-02-19 13:59:47.271426+00', '2026-05-18 13:19:51.117346+00', 'clearkey', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'offline', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('13a8973c-95a3-4338-a116-f5c2889f955d', 'Celestial Classic Movies', 'https://mir-s3-cdn-cf.behance.net/project_modules/1400/7a0c1882445367.5d1d90a91e63c.jpg', 'http://136.158.97.2:6610/001/2/ch00000090990000001244/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20TsXah2%2FZLFNNIdWrVrXDMAp8jImOa2AKrqwa1m%2FJfhcesyK4TH4mOENKJ45mwOyS0g%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001544&contentid=ch00000000000000001544&videoid=ch00000090990000001244&recommendtype=0&userid=1488531249398&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=M5E3S23XZ6XXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO&IASHttpSessionId=RR20449720260101155240980674&ispcode=55', 'mpd', '3b0c1cebd0c4518d600f52c354ed1910', '76d409ffc4eaa012c61d8c31bd13df5d', 'movies', true, 0, '2026-02-19 13:59:47.271426+00', '2026-04-08 02:50:02.925024+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('366512da-05ba-4e94-a556-89d318f95b9d', 'CLTV36', 'https://static.wikia.nocookie.net/logopedia/images/4/48/Cl_tv_36_ph.png/revision/latest?cb=20130823135759', 'http://136.239.173.3:6610/001/2/ch00000090990000001314/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20TsXah2%2FZLFNNIdWrVrXDMAp7Iya5QVRTA1RELFN4tQIJ2%2FjHNuou2Jtxin49X3LQKw%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001814&contentid=ch00000000000000001814&videoid=ch00000090990000001314&recommendtype=0&userid=1662150007478&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=UAIG9NVEJ1AXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO&IASHttpSessionId=RR20446920260101155241033759&ispcode=55', 'mpd', NULL, NULL, 'general', true, 0, '2026-03-07 01:21:46.548149+00', '2026-04-08 02:50:08.944619+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('cf8fa20e-e0a9-4494-ab52-33c01f4426ee', 'DW NEWS', 'https://brandlogos.net/wp-content/uploads/2021/12/deutsche_welle-brandlogo.net_.png', 'http://136.239.158.10:6610/001/2/ch00000090990000001166/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2BoTcUYwq3PMi%2FTObKiSY6bDytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001377&contentid=ch00000000000000001377&videoid=ch00000090990000001166&recommendtype=0&userid=1209889128637&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=GFCSNPUV69DXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', NULL, NULL, 'general', true, 0, '2026-03-21 10:53:47.952974+00', '2026-04-08 02:50:18.381435+00', 'widevine', 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, '["backup2","primary","backup","backup3","backup4","backup5","backup6"]', NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('479af74b-658c-404f-8973-c273583fcce5', 'GMA 7', 'https://philippines.mom-gmr.org/uploads/_processed_/0/4/csm_1011-167_import_5fdc5c345c.png', 'http://136.158.97.2:6610/001/2/ch00000090990000001093/manifest.mpd?AuthInfo=v87HD9rEhwHiAdYyrP20Tg5pgSMSITY%2FHYvvCWJRp%2BoLvT86fM74ocVChyFS93HUytokK1MIobcue1ImXa0ZEA%3D%3D&version=v1.0&BreakPoint=0&virtualDomain=001.live_hls.zte.com&programid=ch00000000000000001214&contentid=ch00000000000000001214&videoid=ch00000090990000001093&recommendtype=0&userid=1084724632836&boid=001&stbid=02%3A00%3A00%3A00%3A00%3A00&terminalflag=1&profilecode=&usersessionid=FGE3OISG4KGXXX&NeedJITP=1&JITPMediaType=DASH&JITPDRMType=NO', 'mpd', NULL, NULL, 'entertainment', true, 0, '2026-02-19 13:59:47.271426+00', '2026-05-15 01:45:11.108675+00', NULL, 'https://ottmdrm.comclark.com/widevine/', NULL, true, NULL, NULL, NULL, 'supabase', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('41262e56-ef82-4cd7-9076-9d39ddaf3961', 'HBO Signature', 'https://th.bing.com/th/id/OIP.PNeE4yWz4_Tp1O-dCdY_xAHaEP?rs=1&pid=ImgDetMain', 'https://qp-pldt-live-bpk-02-prod.akamaized.net/bpk-tv/cg_hbosign/default/index.mpd', 'mpd', 'a06ca6c275744151895762e0346380f5', '559da1b63eec77b5a942018f14d3f56f', 'movies', true, 0, '2026-02-19 14:01:30.092577+00', '2026-04-08 02:50:36.373979+00', 'clearkey', NULL, NULL, true, NULL, NULL, NULL, 'cloudflare', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

INSERT INTO public.channels (id, name, logo_url, stream_url, stream_type, drm_key_id, drm_key, category, is_active, sort_order, created_at, updated_at, license_type, license_url, user_agent, use_proxy, referrer, proxy_order, tvapp_slug, proxy_type, offline_title, offline_message, status, epg_id, channel_num, epg_url)
VALUES ('478763d5-04f0-49ea-bbef-d7a055c74125', 'Myx', 'https://i.imgur.com/CIPTNnT.png', 'https://cdn-ue1-prod.tsv2.amagi.tv/linear/amg01006-abs-cbn-myxnola-dash-abscbnono/index.mpd?app_bundle=&app_name=iwant&app_store_url=&channel_name=MYX&content_id=c6a1bcd7-85a9-4316-95e8-99ba9e6927c1&content_livestream=1&content_producer_name=ABS-CBN&coppa=0&did=438eb073-8f45-5446-a7bc-4ec993e104d9&dnt=0&dur=0&gdpr=0&gdpr_consent=0&genre=Music%2CMusic+Video&ifa_type=PPID&ip=175.158.197.0&language=fil&lmt=0&network_name=ABS-CBN&pmxd=%7B%7BPOD_MAX_DUR_MILLIS%7D%7D&rating=13%2B&sid=a86bcd04-b2a6-455f-a4ec-b1245c4c70ee&title=MYX&ua=Mozilla%2F5.0+%28Windows+NT+10.0%3B+Win64%3B+x64%29+AppleWebKit%2F537.36+%28KHTML%2C+like+Gecko%29+Chrome%2F145.0.0.0+Safari%2F537.36+Edg%2F145.0.0.0&url=https%3A%2F%2Fwww.iwanttfc.com%2Fcontent%2Fc6a1bcd7-85a9-4316-95e8-99ba9e6927c1&us_privacy=1---', 'mpd', 'f40a52a3ac9b4702bdd5b735d910fd2f', '35e4893c6e76546085941be3010932d4', 'music', true, 0, '2026-02-19 14:03:15.902679+00', '2026-04-08 02:51:02.767903+00', 'clearkey', NULL, NULL, false, NULL, NULL, NULL, 'none', NULL, NULL, 'online', NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  logo_url = EXCLUDED.logo_url,
  stream_url = EXCLUDED.stream_url,
  stream_type = EXCLUDED.stream_type,
  drm_key_id = EXCLUDED.drm_key_id,
  drm_key = EXCLUDED.drm_key,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  license_type = EXCLUDED.license_type,
  license_url = EXCLUDED.license_url,
  user_agent = EXCLUDED.user_agent,
  use_proxy = EXCLUDED.use_proxy,
  referrer = EXCLUDED.referrer,
  proxy_order = EXCLUDED.proxy_order,
  tvapp_slug = EXCLUDED.tvapp_slug,
  proxy_type = EXCLUDED.proxy_type,
  offline_title = EXCLUDED.offline_title,
  offline_message = EXCLUDED.offline_message,
  status = EXCLUDED.status,
  epg_id = EXCLUDED.epg_id,
  channel_num = EXCLUDED.channel_num,
  epg_url = EXCLUDED.epg_url;

ALTER TABLE public.channels ENABLE TRIGGER ALL;
