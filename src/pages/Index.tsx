import { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { useChannels, toAppChannel } from '@/hooks/useChannels';
import { LivePlayer } from '@/components/LivePlayer';
import { ScrollArea } from '@/components/ui/scroll-area';
import { type Channel } from '@/lib/channels';
import { cn } from '@/lib/utils';
import { Tv, Search, Shield, User, Loader2, ChevronDown, Monitor, LogIn } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';

const Index = () => {
  const navigate = useNavigate();
  const { data: dbChannels, isLoading } = useChannels();
  
  const [selectedChannel, setSelectedChannel] = useState<Channel | null>(null);
  const [selectedCategory, setSelectedCategory] = useState<string>('All');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [user, setUser] = useState<any>(null);

  // Check auth credentials
  useEffect(() => {
    const checkAuth = async () => {
      try {
        const { data: { user } } = await supabase.auth.getUser();
        setUser(user);
      } catch (error) {
        console.error("Auth check failed:", error);
      }
    };
    checkAuth();
    
    const { data: { subscription } } = supabase.auth.onAuthStateChange(() => {
      checkAuth();
    });
    return () => subscription.unsubscribe();
  }, []);

  // Map database channels to application Channel schema
  const allChannels: Channel[] = useMemo(() => {
    return (dbChannels || []).map(toAppChannel);
  }, [dbChannels]);

  // Set default selected channel on load
  useEffect(() => {
    if (allChannels.length && !selectedChannel) {
      setSelectedChannel(allChannels[0]);
    }
  }, [allChannels, selectedChannel]);

  // Compute unique dynamic categories from database channels
  const categories = useMemo(() => {
    const dbCats = (dbChannels || [])
      .map(c => c.category)
      .filter((cat): cat is string => !!cat && cat.trim().length > 0);
    const uniqueCats = Array.from(new Set(dbCats));
    const formattedCats = uniqueCats.map(cat => cat.charAt(0).toUpperCase() + cat.slice(1));
    return formattedCats.sort();
  }, [dbChannels]);

  // Filter channels based on search and category
  const filteredChannels = useMemo(() => {
    let result = allChannels;

    // Category Filtering
    if (selectedCategory !== 'All') {
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

    return result;
  }, [allChannels, selectedCategory, searchQuery, dbChannels]);

  const handleAdminClick = () => {
    if (user) {
      navigate('/admin');
    } else {
      navigate('/auth');
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
    <div className="h-screen w-full bg-black text-white p-2 md:p-4 lg:p-6 overflow-hidden">
      
      {/* TUNEX MASTER CONTAINER */}
      <div className="h-full w-full flex flex-col bg-[#0a0a0a] tunex-glow rounded-[1.5rem] md:rounded-[2rem] overflow-hidden border border-white/5 relative">

        {/* HEADER */}
        <header className="h-16 md:h-20 px-6 md:px-10 flex items-center justify-between border-b border-white/5 shrink-0 bg-[#0f0f0f]">
          <div className="flex items-center gap-4">
             <div className="w-8 h-8 rounded-lg bg-[#00FF00] shadow-[0_0_20px_rgba(0,255,0,0.4)] flex items-center justify-center">
                <Tv className="w-5 h-5 text-black" />
             </div>
             <h1 className="text-xl md:text-2xl font-black tracking-tighter text-white uppercase italic select-none">
               Flame<span className="text-[#00FF00] not-italic">X</span> Space
             </h1>
          </div>

          <div className="flex items-center gap-3 md:gap-6">
             <div 
               onClick={handleAdminClick}
               className="w-10 h-10 rounded-full bg-zinc-900 border border-white/5 flex items-center justify-center text-zinc-500 hover:text-[#00FF00] transition-colors cursor-pointer group"
               title={user ? 'Admin Panel' : 'Login'}
             >
                {user ? <Shield className="w-5 h-5 group-hover:text-[#00FF00]" /> : <User className="w-5 h-5 group-hover:text-[#00FF00]" />}
             </div>
          </div>
        </header>

        {/* CONTENT AREA */}
        <div className="flex-1 flex flex-col md:flex-row overflow-hidden">
          
          {/* PLAYER ZONE (70%) */}
          <div className="flex-1 p-4 md:p-8 flex items-center justify-center bg-[#050505] relative">
            {selectedChannel ? (
              <div className="w-full max-w-6xl max-h-full aspect-video rounded-2xl overflow-hidden shadow-2xl bg-black border border-white/5 relative group flex items-center justify-center">
                <LivePlayer 
                  key={selectedChannel.id} 
                  channel={selectedChannel} 
                  className="w-full h-full border-none rounded-none bg-transparent"
                />
              </div>
            ) : (
              <div className="flex flex-col items-center gap-6 animate-pulse">
                <div className="w-24 h-24 rounded-full bg-[#00FF00]/5 flex items-center justify-center shadow-[0_0_50px_rgba(0,255,0,0.1)]">
                   <Tv className="w-12 h-12 text-[#00FF00]" />
                </div>
                <span className="text-zinc-600 font-bold uppercase tracking-widest text-sm">Waiting for Selection</span>
              </div>
            )}
          </div>

          {/* CONTROL PANEL / SIDEBAR (30%) */}
          <aside className="w-full md:w-80 lg:w-96 h-full bg-[#121418] border-l border-white/5 flex flex-col shrink-0 overflow-hidden">
            {/* Category Dropdown */}
            <div className="p-4 border-b border-white/5">
              <div className="relative">
                <select 
                  className="w-full bg-zinc-900 border-none text-white text-sm font-bold h-12 px-4 rounded-xl appearance-none cursor-pointer focus:ring-1 focus:ring-[#00FF00]/55 focus:outline-none"
                  value={selectedCategory}
                  onChange={(e) => setSelectedCategory(e.target.value)}
                >
                  <option value="All">All Categories</option>
                  {categories.map(cat => <option key={cat} value={cat}>{cat}</option>)}
                </select>
                <ChevronDown className="absolute right-4 top-1/2 -translate-y-1/2 w-4 h-4 text-zinc-500 pointer-events-none" />
              </div>
            </div>

            {/* Search Input */}
            <div className="p-4 border-b border-white/5">
              <div className="relative">
                <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-zinc-500" />
                <input
                  type="text"
                  placeholder="Search channel..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="w-full bg-zinc-900 border-none text-white h-12 pl-12 rounded-xl placeholder:text-zinc-600 focus-visible:ring-1 focus-visible:ring-[#00FF00]/55 focus:outline-none text-sm"
                />
              </div>
            </div>

            {/* Channel List */}
            <ScrollArea className="flex-1">
              <div className="flex flex-col">
                {filteredChannels.map((channel) => {
                  const isSelected = selectedChannel?.id === channel.id;
                  return (
                    <button
                      key={channel.id}
                      onClick={() => setSelectedChannel(channel)}
                      className={cn(
                        "flex items-center justify-between px-6 py-4 transition-all border-b border-white/5 group text-left w-full",
                        isSelected 
                          ? "bg-[#00FF00] text-black font-black shadow-[0_0_15px_rgba(0,255,0,0.25)]" 
                          : "hover:bg-white/5 text-zinc-400 font-semibold"
                      )}
                    >
                      <div className="flex items-center gap-3 overflow-hidden">
                        <Monitor className={cn("w-4 h-4 shrink-0", isSelected ? "text-black" : "text-zinc-600 group-hover:text-[#00FF00]")} />
                        <span className="truncate text-sm uppercase tracking-wide">{channel.name}</span>
                      </div>
                    </button>
                  );
                })}
              </div>
            </ScrollArea>

            {/* Footer Branding with Login/Admin Button */}
            <div 
              onClick={handleAdminClick}
              className="p-4 bg-[#0a0b0e] border-t border-white/5 flex items-center justify-between cursor-pointer group hover:bg-zinc-900 transition-colors shrink-0"
            >
              <div className="flex items-center gap-2">
                 <Shield className="w-4 h-4 text-zinc-700 group-hover:text-[#00FF00] transition-colors" />
                 <span className="text-[10px] font-black text-zinc-700 group-hover:text-[#00FF00] uppercase tracking-widest transition-colors">Admin Dashboard</span>
              </div>
              <LogIn className="w-4 h-4 text-zinc-700 group-hover:text-[#00FF00] transition-colors" />
            </div>
          </aside>
        </div>

      </div>

      <style>{`
        .tunex-glow {
          box-shadow: 0 0 50px rgba(0, 255, 0, 0.02);
        }
      `}</style>
    </div>
  );
};

export default Index;
