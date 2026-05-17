import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ThemeProvider } from "@/components/ThemeProvider";

import Index from "./pages/Index";
import Movies from "./pages/Movies";
import TVShows from "./pages/TVShows";
import Anime from "./pages/Anime";
import LiveTV from "./pages/LiveTV";
import WatchLive from "./pages/WatchLive";
import LiveEvents from "./pages/LiveEvents";
import WatchEvent from "./pages/WatchEvent";
import Watch from "./pages/Watch";
import Search from "./pages/Search";
import MyList from "./pages/MyList";
import Auth from "./pages/Auth";
import AdminDashboard from "./pages/AdminDashboard";
import Manga from "./pages/Manga";
import MangaDetails from "./pages/MangaDetails";
import MangaReader from "./pages/MangaReader";
import ComickMangaReader from "./pages/ComickMangaReader";
import NotFound from "./pages/NotFound";
import IPTV from "./pages/IPTV";
import PlaylistPlayer from "./pages/PlaylistPlayer";


import TempMail from "./pages/TempMail";
import TextToSpeech from "./pages/TextToSpeech";

import CustomChannels from "./pages/CustomChannels";
import { UpdatePrompt } from '@/components/UpdatePrompt';
import { MaintenanceOverlay } from '@/components/MaintenanceOverlay';
import { AnnouncementBar } from '@/components/AnnouncementBar';
import { SEOManager } from '@/components/SEOManager';
import { useState, useEffect } from "react";
import { useLocation, BrowserRouter, Routes, Route, Link } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";

const queryClient = new QueryClient();

// High-level wrapper to handle route-based maintenance bypass
const MaintenanceWrapper = ({ maintenance, isAdmin, children }: { 
  maintenance: { enabled: boolean; message: string }; 
  isAdmin: boolean; 
  children: React.ReactNode 
}) => {
  const location = useLocation();
  // Bypass maintenance overlay only for /auth and /admin
  const isAuthPage = location.pathname === "/auth" || location.pathname === "/admin";

  if (maintenance.enabled && !isAdmin && !isAuthPage) {
    return <MaintenanceOverlay message={maintenance.message} />;
  }

  return <>{children}</>;
};

import { UserPreferencesProvider } from "@/contexts/UserPreferencesContext";

const App = () => {
  const [maintenance, setMaintenance] = useState({ enabled: false, message: "" });
  const [isAdmin, setIsAdmin] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Safety timeout to prevent infinite loading screen
    const timeout = setTimeout(() => {
      setLoading(false);
    }, 4000);

    const checkMaintenanceAndRole = async () => {
      try {
        // 1. Check Maintenance Setting
        const { data: setting } = await supabase
          .from("site_settings")
          .select("value")
          .eq("key", "maintenance_mode")
          .maybeSingle();

        const maintenanceVal = setting?.value as any;
        if (maintenanceVal?.enabled) {
          setMaintenance(maintenanceVal);
        }

        // 2. Check User Role (for bypass)
        const { data: { user } } = await supabase.auth.getUser();
        if (user) {
          const { data: roles } = await supabase
            .from("user_roles")
            .select("role")
            .eq("user_id", user.id)
            .eq("role", "admin");

          if (roles && roles.length > 0) {
            setIsAdmin(true);
          }
        }
      } catch (error) {
        console.error("Maintenance check failed:", error);
      } finally {
        setLoading(false);
        clearTimeout(timeout);
      }
    };

    checkMaintenanceAndRole();
    
    return () => clearTimeout(timeout);
  }, []);

  if (loading) {
    return (
      <div style={{ 
        position: 'fixed', 
        inset: 0, 
        backgroundColor: '#0b0b0b', 
        color: 'white', 
        display: 'flex', 
        alignItems: 'center', 
        justifyContent: 'center', 
        zIndex: 99999,
        fontFamily: 'sans-serif'
      }}>
        <div style={{ textAlign: 'center' }}>
          <div style={{ 
            width: '40px', 
            height: '40px', 
            border: '3px solid rgba(255,255,255,0.1)', 
            borderTopColor: '#f97316', 
            borderRadius: '50%', 
            animation: 'spin 1s linear infinite',
            margin: '0 auto 16px auto'
          }} />
          <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>
          <p style={{ fontSize: '14px', fontWeight: 'bold', letterSpacing: '0.1em', opacity: 0.6 }}>INITIALIZING...</p>
        </div>
      </div>
    );
  }

  return (
    <QueryClientProvider client={queryClient}>
      <ThemeProvider attribute="class" defaultTheme="dark" enableSystem={false}>
        <BrowserRouter>
          <MaintenanceWrapper maintenance={maintenance} isAdmin={isAdmin}>
            <TooltipProvider>
              <UserPreferencesProvider>
                <SEOManager />
                <Toaster />
                <Sonner />
                <UpdatePrompt />
                <AnnouncementBar />
                
                <div className="pb-16 md:pb-0">
                  <Routes>
                    <Route path="/" element={<Index />} />
                    <Route path="/movies" element={<Movies />} />
                    <Route path="/tv-shows" element={<TVShows />} />
                    <Route path="/anime" element={<Anime />} />
                    <Route path="/manga" element={<Manga />} />
                    <Route path="/manga/:mangaId" element={<MangaDetails />} />
                    <Route path="/manga/:mangaId/read/:chapterId" element={<MangaReader />} />
                    <Route path="/manga/:mangaId/read-comick/:chapterId" element={<ComickMangaReader />} />
                    <Route path="/live-tv" element={<LiveTV />} />
                    <Route path="/live-events" element={<LiveEvents />} />
                    <Route path="/live-event/*" element={<WatchEvent />} />
                    <Route path="/live/:channelId" element={<WatchLive />} />
                    <Route path="/watch/:type/:id" element={<Watch />} />
                    <Route path="/search" element={<Search />} />
                    <Route path="/my-list" element={<MyList />} />
                    <Route path="/auth" element={<Auth />} />
                    <Route path="/admin" element={<AdminDashboard />} />
                    <Route path="/iptv" element={<IPTV />} />
                    <Route path="/temp-mail" element={<TempMail />} />
                    <Route path="/text-to-speech" element={<TextToSpeech />} />
                    <Route path="/custom-channels" element={<CustomChannels />} />
                    <Route path="/playlist-player" element={<PlaylistPlayer />} />

                    <Route path="*" element={<NotFound />} />
                  </Routes>
                </div>
              </UserPreferencesProvider>
            </TooltipProvider>
          </MaintenanceWrapper>
        </BrowserRouter>
      </ThemeProvider>
    </QueryClientProvider>
  );
};

export default App;
