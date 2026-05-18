import { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';
import { Navbar } from '@/components/Navbar';
import { ShareButton } from '@/components/ShareButton';
import { Button } from '@/components/ui/button';
import { ChevronLeft, Radio, ExternalLink, Clock, Play } from 'lucide-react';

const TVAPP_LINK_BASE = 'https://thetvapp.link';

const WatchEvent = () => {
  const { '*': eventSlug } = useParams();
  const [phTime, setPhTime] = useState('');

  useEffect(() => {
    const updateTime = () => {
      setPhTime(
        new Intl.DateTimeFormat('en-PH', {
          hour: '2-digit',
          minute: '2-digit',
          second: '2-digit',
          hour12: true,
          timeZone: 'Asia/Manila',
        }).format(new Date())
      );
    };
    updateTime();
    const interval = setInterval(updateTime, 1000);
    return () => clearInterval(interval);
  }, []);

  const title = eventSlug
    ? eventSlug.split('/').slice(0, 2).pop()?.replace(/-/g, ' ').replace(/\b\w/g, c => c.toUpperCase()) || 'Live Event'
    : 'Live Event';

  const sport = eventSlug?.split('/')[0]?.toUpperCase() || '';
  const sourceUrl = eventSlug ? `${TVAPP_LINK_BASE}/${eventSlug}` : null;

  return (
    <div className="h-[100dvh] bg-background flex flex-col overflow-hidden">
      <Navbar />
      <main className="flex-1 pt-16 overflow-auto pb-12">
        <div className="container mx-auto px-4">
          <div className="py-3">
            <Button asChild variant="ghost" size="sm" className="gap-2">
              <Link to="/live-events">
                <ChevronLeft className="w-4 h-4" />
                Back to Live Events
              </Link>
            </Button>
          </div>

          <div className="max-w-2xl mx-auto w-full">
            {/* Event Card */}
            <div className="bg-card border border-border rounded-2xl p-6 space-y-5">
              {/* Header */}
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  {sport && (
                    <span className="text-xs font-semibold px-2.5 py-1 rounded-full bg-primary/20 text-primary">
                      {sport}
                    </span>
                  )}
                  <div className="flex items-center gap-1.5 text-xs">
                    <Radio className="w-3 h-3 text-destructive animate-pulse" />
                    <span className="text-destructive font-medium">LIVE</span>
                  </div>
                </div>
                <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                  <Clock className="w-3 h-3" />
                  <span>PH Time: {phTime}</span>
                </div>
              </div>

              {/* Title */}
              <h1 className="text-xl font-bold">{title}</h1>

              {/* Player Area / Watch Button */}
              <div className="aspect-video bg-muted/30 rounded-xl flex items-center justify-center border border-border/50">
                <div className="text-center space-y-4">
                  <div className="w-16 h-16 rounded-full bg-primary/20 flex items-center justify-center mx-auto">
                    <Play className="w-8 h-8 text-primary ml-1" />
                  </div>
                  <div>
                    <p className="text-sm text-muted-foreground mb-1">Stream opens in a new tab</p>
                    <p className="text-xs text-muted-foreground">Due to source restrictions, this event plays on the provider's site</p>
                  </div>
                  {sourceUrl && (
                    <Button asChild size="lg" className="gap-2">
                      <a href={sourceUrl} target="_blank" rel="noopener noreferrer">
                        <ExternalLink className="w-4 h-4" />
                        Watch Now
                      </a>
                    </Button>
                  )}
                </div>
              </div>

              {/* Footer */}
              <div className="flex items-center justify-between">
                <ShareButton title={`Watch ${title} - Live`} />
                {sourceUrl && (
                  <a
                    href={sourceUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-xs text-muted-foreground hover:text-foreground transition-colors flex items-center gap-1"
                  >
                    Open source <ExternalLink className="w-3 h-3" />
                  </a>
                )}
              </div>
            </div>
          </div>
        </div>
      </main>
    </div>
  );
};

export default WatchEvent;
