import { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { useChannels, toAppChannel } from '@/hooks/useChannels';
import { LivePlayer } from '@/components/LivePlayer';
import { ScrollArea } from '@/components/ui/scroll-area';
import { type Channel } from '@/lib/channels';
import { cn } from '@/lib/utils';
import { Tv, Search, Shield, User, Loader2, Monitor, Share2, Check } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { supabase } from '@/integrations/supabase/client';

const Index = () => {
  const navigate = useNavigate();
  const { data: dbChannels, isLoading } = useChannels();
  
  const [selectedChannel, setSelectedChannel] = useState<Channel | null>(null);
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [user, setUser] = useState<any>(null);
  const [onlineCount, setOnlineCount] = useState<number>(33);
  const [logoError, setLogoError] = useState<Record<string, boolean>>({});
  const [copiedId, setCopiedId] = useState<string | null>(null);

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

  useEffect(() => {
    const sessionId = `index_user_${Math.random().toString(36).substring(2, 15)}`;
    const channel = supabase.channel('online-users', { config: { presence: { key: sessionId } } });

    channel.on('presence', { event: 'sync' }, () => {
      const state = channel.presenceState();
      setOnlineCount(Math.max(1, Object.keys(state).length));
    }).subscribe(async (status) => {
      if (status === 'SUBSCRIBED') await channel.track({ online_at: new Date().toISOString() });
    });

    return () => { supabase.removeChannel(channel); };
  }, []);

  // Map database channels to application Channel schema
  const allChannels: Channel[] = useMemo(() => {
    return (dbChannels || []).map(toAppChannel);
  }, [dbChannels]);



  // Filter channels based on search
  const filteredChannels = useMemo(() => {
    let result = allChannels;

    // Search Query Filtering
    if (searchQuery.trim().length > 0) {
      result = result.filter(c => 
        c.name.toLowerCase().includes(searchQuery.toLowerCase())
      );
    }

    return result;
  }, [allChannels, searchQuery]);
  const handleAdminClick = () => {
    if (user) {
      navigate('/admin');
    } else {
      navigate('/auth');
    }
  };

  const getInitials = (name: string) => {
    if (!name) return 'TV';
    const parts = name.trim().split(/\s+/);
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return name.slice(0, 2).toUpperCase();
  };

  const handleShare = async (channel: Channel) => {
    try {
      if (channel && channel.manifestUri) {
        await navigator.clipboard.writeText(channel.manifestUri);
        setCopiedId(channel.id);
        setTimeout(() => setCopiedId(null), 2000);
      }
    } catch (err) {
      console.error('Failed to copy stream URI:', err);
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
    <div className="h-[100dvh] w-full bg-black text-white p-0 md:p-4 lg:p-6 overflow-hidden flex flex-col">
      
      {/* TUNEX MASTER CONTAINER */}
      <div className="flex-1 w-full flex flex-col bg-[#0a0a0a] tunex-glow md:rounded-[2rem] overflow-hidden border-0 md:border border-white/5 relative">

        {/* HEADER */}
        <header className="h-16 md:h-20 px-6 md:px-10 flex items-center justify-between border-b border-white/5 shrink-0 bg-[#0f0f0f]">
          <div className="flex items-center gap-3">
             <div className="w-10 h-10 rounded-xl bg-orange-500 flex items-center justify-center shadow-[0_0_15px_rgba(249,115,22,0.3)]">
                <Tv className="w-6 h-6 text-black" fill="black" />
             </div>
             <span className="text-xl md:text-2xl font-black tracking-tighter text-white select-none">
               TV<span className="text-orange-500">STREAMZ</span>
             </span>
             
             <div className="flex items-center gap-2 px-3 py-1 rounded-full bg-zinc-900 border border-white/5 flex">
               <span className="relative flex h-2 w-2 mt-0.5">
                 <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
                 <span className="relative inline-flex rounded-full h-2 w-2 bg-green-500"></span>
               </span>
               <span className="text-[10px] font-black text-zinc-400 uppercase tracking-widest leading-none">{onlineCount} Live</span>
             </div>
          </div>

          {/* Now Playing Pill inside the Header */}
          {selectedChannel && (
            <div className="hidden lg:flex items-center gap-3 px-4 py-2 rounded-2xl bg-zinc-900 border border-white/5 animate-in fade-in duration-300">
              <div className="flex items-center gap-2">
                <span className="relative flex h-2 w-2 mt-0.5">
                  <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75"></span>
                  <span className="relative inline-flex rounded-full h-2 w-2 bg-red-500"></span>
                </span>
                <span className="text-[10px] font-black text-red-500 uppercase tracking-widest leading-none">Playing</span>
              </div>
              <span className="text-zinc-700 font-bold">•</span>
              <span className="text-xs font-black text-white uppercase tracking-wider">{selectedChannel.name}</span>
              <span className="text-zinc-700 font-bold">•</span>
              <span className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider">{selectedChannel.type}</span>
              
              <span className="text-zinc-700 font-bold">•</span>
              <Button 
                onClick={() => handleShare(selectedChannel)}
                variant="ghost" 
                className={cn(
                  "rounded-lg h-7 px-2.5 text-[9px] font-black uppercase tracking-wider gap-1.5 transition-all p-0 hover:bg-white/5",
                  copiedId === selectedChannel.id ? "text-[#00FF00]" : "text-zinc-400 hover:text-white"
                )}
              >
                {copiedId === selectedChannel.id ? (
                  <>
                    <Check className="w-3 h-3" /> Copied
                  </>
                ) : (
                  <>
                    <Share2 className="w-3 h-3" /> Share
                  </>
                )}
              </Button>
            </div>
          )}

          <div className="flex items-center gap-3 md:gap-6">
             <div 
               onClick={handleAdminClick}
               className="w-10 h-10 rounded-full bg-zinc-900 border border-white/5 flex items-center justify-center text-zinc-500 hover:text-orange-500 transition-colors cursor-pointer group"
               title={user ? 'Admin Panel' : 'Login'}
             >
                {user ? <Shield className="w-5 h-5 group-hover:text-orange-500" /> : <User className="w-5 h-5 group-hover:text-orange-500" />}
             </div>
          </div>
        </header>

        {/* CONTENT AREA */}
        <div className="flex-1 flex flex-col md:flex-row overflow-hidden">
          
          {/* PLAYER ZONE (70%) */}
          <div className="w-full md:flex-1 shrink-0 p-0 md:p-8 flex items-center justify-center bg-[#050505] overflow-hidden">
            {selectedChannel ? (
              <div className="w-full max-w-5xl aspect-video md:rounded-2xl overflow-hidden shadow-2xl bg-black border-y md:border border-white/5 relative group flex items-center justify-center animate-in fade-in duration-500 shrink-0">
                <LivePlayer 
                  key={selectedChannel.id} 
                  channel={selectedChannel} 
                  className="w-full h-full border-none rounded-none bg-transparent"
                />
              </div>
            ) : (
              <div className="flex flex-col items-center gap-6 animate-pulse py-12 md:py-0">
                <div className="w-24 h-24 rounded-full bg-[#00FF00]/5 flex items-center justify-center shadow-[0_0_50px_rgba(0,255,0,0.1)]">
                   <Tv className="w-12 h-12 text-[#00FF00]" />
                </div>
                <span className="text-zinc-600 font-bold uppercase tracking-widest text-sm">Waiting for Selection</span>
              </div>
            )}
          </div>

          {/* CONTROL PANEL / SIDEBAR (30%) */}
          <aside className="w-full md:w-80 lg:w-96 flex-1 md:flex-none md:h-full bg-[#121418] border-t md:border-t-0 md:border-l border-white/5 flex flex-col min-h-0 overflow-hidden">


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
                  const hasLogo = channel.logo && channel.logo.trim().length > 0 && !logoError[channel.id];
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
                      <div className="flex items-center gap-4 overflow-hidden">
                        {hasLogo ? (
                          <img 
                            src={channel.logo} 
                            alt={channel.name}
                            onError={() => setLogoError(prev => ({ ...prev, [channel.id]: true }))}
                            className={cn(
                              "w-10 h-10 rounded-full object-contain p-1 border shrink-0 transition-colors bg-zinc-950",
                              isSelected ? "border-black/30" : "border-white/10 group-hover:border-[#00FF00]/40"
                            )}
                          />
                        ) : (
                          <div className={cn(
                            "w-10 h-10 rounded-full flex items-center justify-center font-black text-xs shrink-0 transition-all uppercase border",
                            isSelected 
                              ? "bg-black/20 text-black border-black/30" 
                              : "bg-zinc-900 text-[#00FF00] border-[#00FF00]/20 group-hover:border-[#00FF00]/40 shadow-[0_0_10px_rgba(0,255,0,0.05)]"
                          )}>
                            {getInitials(channel.name)}
                          </div>
                        )}
                        <span className="truncate text-sm uppercase tracking-wider font-bold">{channel.name}</span>
                      </div>
                    </button>
                  );
                })}
              </div>
            </ScrollArea>


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
