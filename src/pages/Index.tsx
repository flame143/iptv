import { useEffect, useState, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { useChannels, toAppChannel } from '@/hooks/useChannels';
import { useUserPreferences } from '@/hooks/useUserPreferences';
import { useProxyLogo } from '@/hooks/useProxyLogo';
import { LivePlayer } from '@/components/LivePlayer';
import { ShareButton } from '@/components/ShareButton';
import { Button } from '@/components/ui/button';
import { type Channel } from '@/lib/channels';
import { cn } from '@/lib/utils';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Tv, Search, Shield, Heart, LogOut, User, Loader2 } from 'lucide-react';

const Index = () => {
  const navigate = useNavigate();
  const { data: dbChannels, isLoading } = useChannels();
  const { isInMyList, addToMyList, removeFromMyList, myList } = useUserPreferences();
  const { proxyLogo } = useProxyLogo();

  const [selectedChannel, setSelectedChannel] = useState<Channel | null>(null);
  const [selectedCategory, setSelectedCategory] = useState<string>('All');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [proxyStatus, setProxyStatus] = useState<string>('');
  const [isAdmin, setIsAdmin] = useState<boolean>(false);
  const [isLoggedIn, setIsLoggedIn] = useState<boolean>(false);

  // Check user credentials and roles
  useEffect(() => {
    const checkAuthAndRole = async () => {
      try {
        const { data: { user } } = await supabase.auth.getUser();
        setIsLoggedIn(!!user);
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
        console.error("Auth status check failed:", error);
      }
    };

    checkAuthAndRole();

    const { data: { subscription } } = supabase.auth.onAuthStateChange(() => {
      checkAuthAndRole();
    });

    return () => subscription.unsubscribe();
  }, []);

  // Map all channels to format used by player
  const allChannels: Channel[] = useMemo(() => {
    return (dbChannels || []).map(toAppChannel);
  }, [dbChannels]);

  // Compute unique dynamic categories from database channels
  const categories = useMemo(() => {
    const dbCats = (dbChannels || [])
      .map(c => c.category)
      .filter((cat): cat is string => !!cat && cat.trim().length > 0);
    const uniqueCats = Array.from(new Set(dbCats));
    const formattedCats = uniqueCats.map(cat => cat.charAt(0).toUpperCase() + cat.slice(1));
    return ['All', 'Favorites', ...formattedCats.sort()];
  }, [dbChannels]);

  // Filter and Search channels list
  const filteredChannels = useMemo(() => {
    let result = allChannels;

    // Category Filtering
    if (selectedCategory === 'Favorites') {
      const favoriteIds = myList
        .filter(item => item.type === 'channel')
        .map(item => String(item.id));
      result = result.filter(c => favoriteIds.includes(String(c.id)));
    } else if (selectedCategory !== 'All') {
      result = result.filter(c => {
        const dbCh = (dbChannels || []).find(d => d.id === c.id);
        const cat = dbCh?.category || 'general';
        return cat.toLowerCase() === selectedCategory.toLowerCase();
      });
    }

    // Search Query Filtering
    if (searchQuery.trim().length > 0) {
      result = result.filter(c => 
        c.name.toLowerCase().includes(searchQuery.toLowerCase())
      );
    }

    // Sort Alphabetically
    return [...result].sort((a, b) => a.name.localeCompare(b.name));
  }, [allChannels, selectedCategory, searchQuery, myList, dbChannels]);

  // Favorite helpers
  const isFavorite = (id: string) => isInMyList(id, 'channel');

  const toggleFavorite = (targetChannel: Channel) => {
    if (isInMyList(targetChannel.id, 'channel')) {
      removeFromMyList(targetChannel.id, 'channel');
      toast.success(`${targetChannel.name} removed from favorites`);
    } else {
      addToMyList({
        id: targetChannel.id,
        type: 'channel',
        title: targetChannel.name,
        poster_path: targetChannel.logo,
      });
      toast.success(`${targetChannel.name} added to favorites`);
    }
  };

  if (isLoading) {
    return (
      <div className="min-h-screen bg-[#030303] flex flex-col items-center justify-center gap-3">
        <Loader2 className="w-10 h-10 text-[#00FF00] animate-spin" />
        <p className="text-[10px] text-zinc-500 font-black tracking-widest uppercase">LOADING CHANNELS...</p>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-[#030303] bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-blue-950/10 via-zinc-950 to-black text-white p-4 md:p-6 flex items-center justify-center">
      {/* Outer Sleek App Container */}
      <div className="w-full max-w-[1400px] bg-[#09090b] rounded-[2rem] border border-zinc-900/80 shadow-[0_0_50px_rgba(0,100,255,0.12)] overflow-hidden flex flex-col min-h-[calc(100vh-3rem)]">
        
        {/* Header Bar */}
        <header className="flex items-center justify-between px-6 py-5 border-b border-zinc-900/80 bg-zinc-950/30 backdrop-blur-md">
          {/* Logo Section */}
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl bg-black border border-[#00FF00]/30 flex items-center justify-center shadow-[0_0_15px_rgba(0,255,0,0.15)]">
              <Tv className="w-4 h-4 text-[#00FF00]" strokeWidth={2.5} />
            </div>
            <span className="text-lg font-black tracking-tighter text-white uppercase flex items-center gap-0.5 select-none">
              FLAME<span className="text-[#00FF00] italic font-black text-xl mx-0.5">X</span>SPACE
            </span>
          </div>

          {/* User Profile / Auth State Action */}
          <div>
            <Button
              variant="ghost"
              size="icon"
              onClick={() => navigate('/auth')}
              className="w-10 h-10 rounded-full bg-zinc-900 border border-zinc-800 text-zinc-400 hover:text-white hover:bg-zinc-800 transition-all shadow-lg shadow-black/30"
            >
              <User className="w-4 h-4" />
            </Button>
          </div>
        </header>

        {/* Dynamic Two-Column Layout */}
        <div className="flex-1 grid grid-cols-1 lg:grid-cols-3 overflow-hidden">
          
          {/* Left Column: Player Area */}
          <div className="lg:col-span-2 p-6 flex flex-col gap-4 border-r border-zinc-900/80 justify-center">
            {selectedChannel ? (
              <div className="flex flex-col gap-5 flex-1 justify-center animate-fade-in">
                {/* Custom Video Player Box */}
                <div className="relative aspect-video w-full rounded-2xl overflow-hidden border border-zinc-900 bg-black shadow-2xl">
                  <LivePlayer 
                    channel={selectedChannel} 
                    onProxyChange={setProxyStatus} 
                  />
                </div>

                {/* Player Metadata & Controllers */}
                <div className="flex flex-col sm:flex-row sm:items-center justify-between p-4 bg-zinc-950 border border-zinc-900 rounded-2xl gap-4">
                  <div className="flex items-center gap-3.5">
                    <img
                      src={proxyLogo(selectedChannel.logo)}
                      alt={selectedChannel.name}
                      className="w-12 h-12 object-contain rounded-xl bg-zinc-900 border border-zinc-800 p-2"
                      onError={(e) => {
                        e.currentTarget.src = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="%2300ff00" stroke-width="2"><rect width="20" height="15" x="2" y="7" rx="2" ry="2"/><polyline points="17 2 12 7 7 2"/></svg>';
                      }}
                    />
                    <div>
                      <h2 className="text-base font-bold text-white tracking-tight leading-snug">{selectedChannel.name}</h2>
                      <div className="flex items-center gap-2 mt-1">
                        <span className="w-1.5 h-1.5 rounded-full bg-[#00FF00] animate-ping" />
                        <span className="text-[9px] text-[#00FF00] font-black tracking-widest uppercase">
                          {proxyStatus || 'DIRECT CONNECTION'}
                        </span>
                      </div>
                    </div>
                  </div>

                  <div className="flex items-center gap-2 self-end sm:self-auto">
                    {/* Share Content */}
                    <ShareButton title={`Watch ${selectedChannel.name} Live on FLAME X SPACE`} />

                    {/* Favorite Toggler */}
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => toggleFavorite(selectedChannel)}
                      className={cn(
                        "rounded-xl transition-all duration-300 h-11 w-11 border border-zinc-800",
                        isFavorite(selectedChannel.id)
                          ? "text-[#00FF00] bg-[#00FF00]/10 hover:bg-[#00FF00]/20 border-[#00FF00]/30 shadow-[0_0_15px_rgba(0,255,0,0.15)]"
                          : "text-zinc-400 bg-zinc-900/50 hover:text-white hover:bg-zinc-800"
                      )}
                    >
                      <Heart className={cn("w-4.5 h-4.5", isFavorite(selectedChannel.id) && "fill-current")} />
                    </Button>
                  </div>
                </div>
              </div>
            ) : (
              /* WAITING FOR SELECTION State Placeholder */
              <div className="flex-1 flex flex-col items-center justify-center text-center p-8 bg-zinc-950/10 rounded-3xl border border-dashed border-zinc-900/80 min-h-[350px] lg:min-h-[450px]">
                <div className="relative mb-6">
                  {/* Neon pulsing glow */}
                  <div className="absolute -inset-6 bg-[#00FF00]/10 rounded-full blur-2xl animate-pulse" />
                  
                  <div className="w-20 h-20 rounded-2xl bg-zinc-900 border border-zinc-800/80 flex items-center justify-center text-[#00FF00] shadow-[0_0_30px_rgba(0,255,0,0.12)] relative">
                    <Tv className="w-10 h-10 text-[#00FF00]" strokeWidth={1.8} />
                    <div className="absolute bottom-2 right-2 w-3.5 h-3.5 bg-[#00FF00] border-2 border-zinc-900 rounded-full animate-ping" />
                    <div className="absolute bottom-2 right-2 w-3.5 h-3.5 bg-[#00FF00] border-2 border-zinc-900 rounded-full" />
                  </div>
                </div>
                <h3 className="text-lg font-black text-white tracking-widest uppercase">WAITING FOR SELECTION</h3>
                <p className="text-xs text-zinc-500 max-w-sm mt-2 leading-relaxed">
                  Select a live TV channel from the sidebar selector to begin streaming high-definition broadcast media.
                </p>
              </div>
            )}
          </div>

          {/* Right Column: Sidebar Navigation */}
          <div className="lg:col-span-1 p-6 flex flex-col gap-4 bg-zinc-950/30">
            {/* Category Dropdown */}
            <div className="relative">
              <Select value={selectedCategory} onValueChange={setSelectedCategory}>
                <SelectTrigger className="w-full bg-[#18181b] border-none text-white font-bold h-12 rounded-xl focus:ring-1 focus:ring-[#00FF00]/50 transition-all px-4 focus-visible:outline-none">
                  <SelectValue placeholder="Select Category" />
                </SelectTrigger>
                <SelectContent className="bg-[#18181b] border-zinc-800 text-white rounded-xl">
                  {categories.map((cat) => (
                    <SelectItem key={cat} value={cat} className="hover:bg-zinc-800 focus:bg-zinc-800 cursor-pointer">
                      {cat === 'All' ? 'All Channels' : cat}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {/* Live Search Input */}
            <div className="relative">
              <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-zinc-500" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search channel..."
                className="w-full bg-[#18181b] border-none text-white text-sm h-12 rounded-xl pl-12 pr-4 focus:outline-none focus:ring-1 focus:ring-[#00FF00]/50 placeholder:text-zinc-500 transition-all"
              />
            </div>

            {/* Scrollable Channel Buttons List */}
            <div className="flex-1 overflow-y-auto pr-1 space-y-1.5 min-h-[300px] max-h-[380px] lg:max-h-none scrollbar-thin scrollbar-thumb-zinc-800">
              {filteredChannels.map((ch) => {
                const active = selectedChannel?.id === ch.id;
                return (
                  <button
                    key={ch.id}
                    onClick={() => {
                      setSelectedChannel(ch);
                      setProxyStatus('');
                    }}
                    className={cn(
                      "w-full flex items-center justify-between p-3.5 rounded-xl transition-all text-left group",
                      active
                        ? "bg-[#00FF00] text-black font-extrabold shadow-[0_0_20px_rgba(0,255,0,0.22)] scale-[1.01]"
                        : "text-zinc-400 hover:text-white hover:bg-white/5 bg-transparent"
                    )}
                  >
                    <div className="flex items-center gap-3">
                      <Tv className={cn(
                        "w-4 h-4 flex-shrink-0 transition-colors",
                        active ? "text-black" : "text-zinc-500 group-hover:text-[#00FF00]"
                      )} />
                      <span className="text-sm font-semibold tracking-tight truncate max-w-[190px]">{ch.name}</span>
                    </div>

                    {active ? (
                      <div className="w-1.5 h-1.5 rounded-full bg-black animate-pulse" />
                    ) : (
                      <span className="text-[10px] text-zinc-600 font-bold group-hover:text-zinc-500 transition-colors uppercase">
                        {ch.category || 'General'}
                      </span>
                    )}
                  </button>
                );
              })}

              {filteredChannels.length === 0 && (
                <div className="py-16 text-center text-zinc-600 text-xs flex flex-col items-center gap-2">
                  <Tv className="w-8 h-8 opacity-25" />
                  <span>No channels found.</span>
                </div>
              )}
            </div>

            {/* Static Bottom Admin Console Redirection */}
            <div className="pt-4 border-t border-zinc-900/80 mt-auto">
              <Button
                variant="ghost"
                onClick={() => navigate(isAdmin ? '/admin' : '/auth')}
                className="w-full bg-zinc-900/30 hover:bg-zinc-900/60 border border-zinc-900/60 text-zinc-400 hover:text-white text-xs font-bold uppercase tracking-wider rounded-xl py-5 px-4 flex items-center justify-between group shadow-sm transition-all"
              >
                <div className="flex items-center gap-2.5">
                  <Shield className="w-4 h-4 text-[#00FF00]" />
                  <span>Admin Dashboard</span>
                </div>
                <LogOut className="w-3.5 h-3.5 text-zinc-600 group-hover:text-zinc-400 transition-colors" />
              </Button>
            </div>
          </div>

        </div>

      </div>
    </div>
  );
};

export default Index;
