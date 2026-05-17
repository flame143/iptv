import { useState, useEffect } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { Search, Tv, Film, MonitorPlay, Home, Sparkles, Users, Menu, ListVideo, Clock, Mail, Shield, MonitorUp, ListMusic } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';

import { NotificationBell } from './NotificationBell';
import { SearchSuggestions } from './SearchSuggestions';
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from '@/components/ui/sheet';
import { useUserPreferences } from '@/hooks/useUserPreferences';

export const Navbar = () => {
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  const [onlineCount, setOnlineCount] = useState(0);
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  
  // BAGO: Kukunin ang bilang direkta sa hook para laging updated
  const { myList } = useUserPreferences();
  
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [isAdmin, setIsAdmin] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  const location = useLocation();
  const navigate = useNavigate();

  useEffect(() => {
    const handleScroll = () => {
      setScrolled(window.scrollY > 50);
    };
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const isHome = location.pathname === '/';

  useEffect(() => {
    const checkAuth = async () => {
      const { data: { user } } = await supabase.auth.getUser();
      setIsLoggedIn(!!user);
      if (user) {
        const { data: roles } = await supabase
          .from("user_roles")
          .select("role")
          .eq("user_id", user.id)
          .eq("role", "admin");
        setIsAdmin(!!(roles && roles.length > 0));
      } else {
        setIsAdmin(false);
      }
    };
    checkAuth();
    const { data: { subscription } } = supabase.auth.onAuthStateChange(() => {
      checkAuth();
    });
    return () => subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (isMenuOpen) {
      // BAGO: Tinanggal ang setMyListCount dito dahil matik na yan sa hook
    }
  }, [isMenuOpen]);

  useEffect(() => {
    const sessionId = `user_${Math.random().toString(36).substring(2, 15)}`;
    const channel = supabase.channel('online-users', { config: { presence: { key: sessionId } } });

    channel.on('presence', { event: 'sync' }, () => {
      const state = channel.presenceState();
      setOnlineCount(Math.max(1, Object.keys(state).length));
    }).subscribe(async (status) => {
      if (status === 'SUBSCRIBED') await channel.track({ online_at: new Date().toISOString() });
    });

    return () => { supabase.removeChannel(channel); };
  }, []);

  const navItems = [
    { path: '/', label: 'Live TV', icon: Tv },
  ];

  return (
    <nav className={`fixed top-0 left-0 right-0 z-50 transition-all duration-500 ${
      scrolled || !isHome 
        ? 'bg-background/80 backdrop-blur-2xl border-b border-border py-4 shadow-2xl' 
        : 'bg-transparent py-6'
    }`}>
      <div className="container mx-auto px-4 md:px-12">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-6">
            <Link to="/" className="flex items-center gap-3 group">
              <div className="w-10 h-10 rounded-xl bg-[#00FF00] flex items-center justify-center shadow-[0_0_15px_rgba(0,255,0,0.3)] transition-transform group-hover:scale-110">
                <Tv className="w-6 h-6 text-black" fill="black" />
              </div>
              <span className="text-2xl font-black tracking-tighter text-foreground hidden sm:block">
                FLAME<span className="text-[#00FF00]">X</span>SPACE
              </span>
            </Link>
            
            <div className={`flex items-center gap-2 px-3 py-1 rounded-full bg-muted border border-border transition-opacity duration-500 ${scrolled ? 'opacity-100' : 'opacity-60'}`}>
              <span className="relative flex h-2 w-2">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
                <span className="relative inline-flex rounded-full h-2 w-2 bg-green-500"></span>
              </span>
              <span className="text-[10px] font-black text-zinc-400 uppercase tracking-widest">{onlineCount.toLocaleString()} Live</span>
            </div>
          </div>

          <div className="hidden lg:flex items-center gap-1 bg-muted p-1 rounded-2xl border border-border">
            {navItems.map((item) => {
              const Icon = item.icon;
              const isActive = location.pathname === item.path;
              return (
                <Link 
                  key={item.path} 
                  to={item.path} 
                  className={`flex items-center gap-2 px-6 py-2 rounded-xl text-xs font-black uppercase tracking-widest transition-all duration-300 ${
                    isActive 
                      ? 'bg-[#00FF00] text-black shadow-lg shadow-[#00FF00]/20' 
                      : 'text-muted-foreground hover:text-foreground hover:bg-background/50'
                  }`}
                >
                  <Icon className="w-4 h-4" />
                  {item.label}
                </Link>
              );
            })}
          </div>

          <div className="flex items-center gap-3">
            <div className={`flex items-center transition-all duration-500 ease-in-out ${isSearchOpen ? 'w-64 md:w-80' : 'w-10'}`}>
              {isSearchOpen ? (
                <SearchSuggestions isOpen={isSearchOpen} onClose={() => setIsSearchOpen(false)} />
              ) : (
                <Button 
                  variant="ghost" 
                  size="icon" 
                  onClick={() => setIsSearchOpen(true)} 
                  className="w-12 h-12 rounded-xl bg-muted border border-border hover:bg-accent hover:text-accent-foreground text-foreground transition-all hover:scale-105"
                >
                  <Search className="w-5 h-5" />
                </Button>
              )}
            </div>


            <NotificationBell />
            
            <Sheet open={isMenuOpen} onOpenChange={setIsMenuOpen}>
              <SheetTrigger asChild>
                <Button 
                  variant="ghost" 
                  size="icon" 
                  className="w-12 h-12 rounded-xl bg-muted border border-border hover:bg-accent hover:text-accent-foreground text-foreground transition-all hover:scale-105"
                >
                  <Menu className="w-6 h-6" />
                </Button>
              </SheetTrigger>
              <SheetContent side="right" className="w-80 bg-background border-border p-0 overflow-hidden">
                <div className="h-full flex flex-col pt-20 px-6">
                  <div className="mb-8">
                     <p className="text-[10px] font-black text-zinc-500 uppercase tracking-[0.3em] mb-4">Your Account</p>
                     {!isLoggedIn ? (
                        <Button asChild className="w-full h-14 rounded-2xl bg-[#00FF00] hover:bg-[#00FF00]/80 text-black font-black uppercase tracking-widest gap-3">
                          <Link to="/auth" onClick={() => setIsMenuOpen(false)}>
                            <Shield className="w-5 h-5" />
                            Sign In / Register
                          </Link>
                        </Button>
                     ) : (
                        <div className="p-4 rounded-2xl bg-muted border border-border flex items-center gap-3">
                           <div className="w-10 h-10 rounded-full bg-[#00FF00] flex items-center justify-center font-black text-black">A</div>
                           <div>
                              <p className="font-black text-sm uppercase tracking-tight">Active User</p>
                              <p className="text-[10px] text-zinc-500">Premium Member</p>
                           </div>
                        </div>
                     )}
                  </div>

                  <div className="space-y-4">
                    <p className="text-[10px] font-black text-zinc-500 uppercase tracking-[0.3em] mb-4">Library</p>
                    
                    <Link to="/my-list" onClick={() => setIsMenuOpen(false)} className="group flex items-center justify-between p-4 rounded-2xl bg-muted hover:bg-accent border border-border transition-all">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center group-hover:scale-110 transition-transform">
                          <ListVideo className="w-5 h-5 text-primary" />
                        </div>
                        <div>
                          <p className="font-black text-xs uppercase tracking-widest">My List</p>
                          {/* BAGO: Ginamit ang myList.length mula sa hook */}
                          <p className="text-[10px] text-zinc-500">{myList.length} items saved</p>
                        </div>
                      </div>
                    </Link>

                    <Link to="/playlist-player" onClick={() => setIsMenuOpen(false)} className="group flex items-center justify-between p-4 rounded-2xl bg-white/5 hover:bg-white/10 border border-white/5 transition-all">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center group-hover:scale-110 transition-transform">
                          <ListMusic className="w-5 h-5 text-primary" />
                        </div>
                        <div>
                          <p className="font-black text-xs uppercase tracking-widest">Playlist Player</p>
                          <p className="text-[10px] text-zinc-500">M3U & DRM Player</p>
                        </div>
                      </div>
                    </Link>

                    <Link to="/temp-mail" onClick={() => setIsMenuOpen(false)} className="group flex items-center justify-between p-4 rounded-2xl bg-white/5 hover:bg-white/10 border border-white/5 transition-all">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-xl bg-blue-500/10 flex items-center justify-center group-hover:scale-110 transition-transform">
                          <Mail className="w-5 h-5 text-blue-500" />
                        </div>
                        <div>
                          <p className="font-black text-xs uppercase tracking-widest">Temp Mail</p>
                          <p className="text-[10px] text-zinc-500">Disposable inbox</p>
                        </div>
                      </div>
                    </Link>

                    {isAdmin && (
                      <Link to="/admin" onClick={() => setIsMenuOpen(false)} className="group flex items-center justify-between p-4 rounded-2xl bg-destructive/10 hover:bg-destructive/20 border border-destructive/20 transition-all">
                        <div className="flex items-center gap-3">
                          <div className="w-10 h-10 rounded-xl bg-destructive/20 flex items-center justify-center group-hover:scale-110 transition-transform">
                            <Shield className="w-5 h-5 text-destructive" />
                          </div>
                          <div>
                            <p className="font-black text-xs uppercase tracking-widest text-destructive">Admin Console</p>
                            <p className="text-[10px] text-destructive-foreground opacity-50">Manage Platform</p>
                          </div>
                        </div>
                      </Link>
                    )}
                  </div>
                </div>
              </SheetContent>
            </Sheet>
          </div>
        </div>
      </div>
    </nav>
  );
};
