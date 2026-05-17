import { useMemo, useState, useCallback, useEffect } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import { Navbar } from '@/components/Navbar';
import { LivePlayer } from '@/components/LivePlayer';
import { ShareButton } from '@/components/ShareButton';
import { type Channel } from '@/lib/channels';
import { useChannels, toAppChannel } from '@/hooks/useChannels';
import { useChannelViews, trackChannelView } from '@/hooks/useChannelViews';
import { ChevronLeft, Loader2, ArrowUpAZ, TrendingUp, Clock, Heart, Star } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { ScrollArea } from '@/components/ui/scroll-area';
import { useUserPreferences } from '@/hooks/useUserPreferences';
import { useProxyLogo } from '@/hooks/useProxyLogo';
import { cn } from '@/lib/utils';
import { toast } from 'sonner';
import { CATEGORIES } from '@/lib/channelCategories';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

type SortOption = 'a-z' | 'popular' | 'recent';

const WatchLive = () => {
  const { channelId } = useParams<{ channelId: string }>();
  const navigate = useNavigate();
  const [sortBy, setSortBy] = useState<SortOption>('a-z');
  const [selectedCategory, setSelectedCategory] = useState<string>('All');
  
  const { data: dbChannels, isLoading } = useChannels();
  const { data: viewCounts } = useChannelViews();
  const { isInMyList, addToMyList, removeFromMyList, myList, isLoading: isPrefsLoading } = useUserPreferences();
  const { proxyLogo } = useProxyLogo();

  // All channels from database
  const allChannels: Channel[] = useMemo(() => {
    return (dbChannels || []).map(toAppChannel);
  }, [dbChannels]);

  const channel = useMemo(() => {
    return allChannels.find((c) => c.id.toLowerCase() === channelId?.toLowerCase());
  }, [allChannels, channelId]);

  // Track channel view
  useEffect(() => {
    if (channel) {
      trackChannelView(channel.id, channel.name);
    }
  }, [channel?.id, channel?.name]);

  const isFavorite = channel ? isInMyList(channel.id, 'channel') : false;

  const toggleFavorite = (targetChannel: Channel, e?: React.MouseEvent) => {
    if (e) {
      e.preventDefault();
      e.stopPropagation();
    }
    
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

  // Sort and Filter other channels based on selected options
  const sortedOtherChannels = useMemo(() => {
    let others = allChannels.filter((c) => c.id !== channelId);
    
    // Category Filtering
    if (selectedCategory === 'Favorites') {
      const favoriteIds = myList
        .filter(item => item.type === 'channel')
        .map(item => String(item.id));
      others = others.filter(c => favoriteIds.includes(String(c.id)));
    } else if (selectedCategory !== 'All') {
      others = others.filter(c => {
        const dbCh = (dbChannels || []).find(d => d.id === c.id);
        const cat = dbCh?.category || 'general';
        return cat.toLowerCase() === selectedCategory.toLowerCase();
      });
    }

    switch (sortBy) {
      case 'a-z':
        return [...others].sort((a, b) => a.name.localeCompare(b.name));
      case 'popular':
        return [...others].sort((a, b) => {
          const aViews = viewCounts?.[a.id] || 0;
          const bViews = viewCounts?.[b.id] || 0;
          if (bViews !== aViews) return bViews - aViews;
          return a.name.localeCompare(b.name);
        });
      case 'recent':
        return [...others].sort((a, b) => {
          const aDb = (dbChannels || []).find(ch => ch.id === a.id);
          const bDb = (dbChannels || []).find(ch => ch.id === b.id);
          if (aDb && bDb) {
            return new Date(bDb.created_at).getTime() - new Date(aDb.created_at).getTime();
          }
          return a.name.localeCompare(b.name);
        });
      default:
        return others;
    }
  }, [allChannels, channelId, viewCounts, dbChannels, sortBy, selectedCategory, myList]);

  const handleChannelSwitch = useCallback((newChannelId: string) => {
    navigate(`/live/${newChannelId}`, { replace: true });
  }, [navigate]);

  if (isLoading) {
    return (
      <div className="h-[100dvh] bg-background flex items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (!channel) {
    return (
      <div className="h-[100dvh] bg-background">
        <Navbar />
        <div className="pt-24 container mx-auto px-4 text-center">
          <h1 className="text-2xl font-bold mb-4">Channel not found</h1>
          <Button asChild>
            <Link to="/live-tv">Back to Live TV</Link>
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="h-[100dvh] bg-background flex flex-col overflow-hidden">
      <Navbar />

      {/* Main Page Scroll */}
      <ScrollArea className="flex-1 min-h-0 pt-16">
        <main className="pb-12">
          <div className="container mx-auto px-4">
            {/* Back Button */}
            <div className="py-3">
              <Button asChild variant="ghost" size="sm" className="gap-2">
                <Link to="/live-tv">
                  <ChevronLeft className="w-4 h-4" />
                  Back to Live TV
                </Link>
              </Button>
            </div>

            {/* Player Section */}
            <div className="max-w-4xl mx-auto w-full">
              {/* Channel Info */}
              <div className="flex items-center justify-between mb-3">
                <div className="flex items-center gap-3">
                  <img
                    src={proxyLogo(channel.logo)}
                    alt={channel.name}
                    className="w-10 h-10 object-contain rounded-lg bg-secondary p-1.5"
                  />
                  <div>
                    <h1 className="text-lg font-bold">{channel.name}</h1>
                  </div>
                </div>
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={(e) => toggleFavorite(channel, e)}
                  className={cn(
                    "rounded-full transition-all duration-300 h-10 w-10",
                    isFavorite 
                      ? "text-primary bg-primary/10 hover:bg-primary/20 shadow-[0_0_15px_rgba(234,179,8,0.2)]" 
                      : "text-muted-foreground hover:text-foreground hover:bg-secondary"
                  )}
                >
                  <Heart className={cn("w-5 h-5", isFavorite && "fill-current scale-110")} />
                </Button>
              </div>

              {/* Player */}
              <LivePlayer 
                channel={channel}
              />

              {/* Share Button & Optional Metadata */}
              <div className="flex justify-start mt-3">
                <ShareButton title={`Watch ${channel.name} - Live TV`} />
              </div>
            </div>

            {/* Other Channels - Separate Scrollable Section */}
            {allChannels.length > 1 && (
              <div className="mt-6 max-w-4xl mx-auto w-full">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-3">
                  <h2 className="text-sm font-semibold">Other Channels</h2>
                  
                  <div className="flex items-center gap-2">
                    {/* Category Filter */}
                    <Select value={selectedCategory} onValueChange={setSelectedCategory}>
                      <SelectTrigger className="w-[140px] h-8 text-xs bg-card">
                        <SelectValue placeholder="Genre" />
                      </SelectTrigger>
                      <SelectContent className="bg-popover">
                        {CATEGORIES.map(cat => (
                          <SelectItem key={cat} value={cat}>
                            <div className="flex items-center gap-2">
                              {cat === 'Favorites' ? <Star className="w-3 h-3 text-primary" /> : <div className="w-3" />}
                              <span>{cat === 'All' ? 'All Channels' : cat}</span>
                            </div>
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>

                    {/* Sort Dropdown */}
                    <Select value={sortBy} onValueChange={(value: SortOption) => setSortBy(value)}>
                      <SelectTrigger className="w-[120px] h-8 text-xs bg-card">
                        <SelectValue placeholder="Sort" />
                      </SelectTrigger>
                      <SelectContent className="bg-popover">
                        <SelectItem value="a-z">
                          <div className="flex items-center gap-2">
                            <ArrowUpAZ className="w-3 h-3" />
                            <span>A-Z</span>
                          </div>
                        </SelectItem>
                        <SelectItem value="popular">
                          <div className="flex items-center gap-2">
                            <TrendingUp className="w-3 h-3" />
                            <span>Popular</span>
                          </div>
                        </SelectItem>
                        <SelectItem value="recent">
                          <div className="flex items-center gap-2">
                            <Clock className="w-3 h-3" />
                            <span>Recent</span>
                          </div>
                        </SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                </div>
                
                <div className="border border-border rounded-xl bg-card/50 p-3">
                  <ScrollArea className="h-[280px]">
                    <div className="grid grid-cols-4 sm:grid-cols-5 md:grid-cols-6 lg:grid-cols-8 gap-2 pr-3">
                      {sortedOtherChannels.map((ch) => {
                        const isFav = isInMyList(ch.id, 'channel');
                        return (
                          <div key={ch.id} className="relative group">
                            <button
                              onClick={() => handleChannelSwitch(ch.id)}
                              className="w-full flex flex-col items-center p-2 rounded-lg bg-background border border-border hover:border-primary/50 hover:bg-accent/50 transition-all duration-200"
                            >
                              <img
                                src={proxyLogo(ch.logo)}
                                alt={ch.name}
                                className="w-8 h-8 sm:w-10 sm:h-10 object-contain rounded-md bg-secondary/50 p-1"
                              />
                              <p className="font-medium text-[9px] sm:text-[10px] group-hover:text-primary transition-colors text-center mt-1.5 line-clamp-1 w-full">
                                {ch.name}
                              </p>
                            </button>
                            <button
                              onClick={(e) => toggleFavorite(ch, e)}
                              className={cn(
                                "absolute top-1 right-1 w-5 h-5 rounded-full flex items-center justify-center transition-all duration-300 z-10 backdrop-blur-md",
                                isFav 
                                  ? "bg-primary/20 text-primary opacity-100" 
                                  : "bg-black/40 text-white/70 opacity-0 group-hover:opacity-100 hover:text-white"
                              )}
                            >
                              <Heart className={cn("w-2.5 h-2.5", isFav && "fill-current")} />
                            </button>
                          </div>
                        );
                      })}

                      {sortedOtherChannels.length === 0 && (
                        <div className="col-span-full flex flex-col items-center justify-center py-12 text-center">
                          {selectedCategory === 'Favorites' ? (
                            <>
                              <Heart className="w-8 h-8 mb-2 text-muted-foreground opacity-20" />
                              <p className="text-xs text-muted-foreground">No other favorites found.</p>
                              <Button variant="link" size="sm" onClick={() => setSelectedCategory('All')} className="text-primary text-[10px] mt-1">
                                Browse All Channels
                              </Button>
                            </>
                          ) : (
                            <p className="text-xs text-muted-foreground">No channels found in this category.</p>
                          )}
                        </div>
                      )}
                    </div>
                  </ScrollArea>
                </div>
              </div>
            )}
          </div>
        </main>
      </ScrollArea>
    </div>
  );
};

export default WatchLive;
