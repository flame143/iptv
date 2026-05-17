import { useEffect, useRef, useState, useMemo, useCallback } from 'react';
import { YouTubePlayer } from './YouTubePlayer';
import { PlayerOSD } from './PlayerOSD';
import { Channel, type ProxyKey, DEFAULT_PROXY_ORDER } from '@/lib/channels';
import { AlertCircle, Loader2, Smartphone, Settings, Check, Shield, RefreshCw } from 'lucide-react';
import Hls from 'hls.js';
import shaka from 'shaka-player/dist/shaka-player.ui';
import 'shaka-player/dist/controls.css';
import { supabase } from '@/integrations/supabase/client';
import { setupOrientationFullscreen } from '@/lib/capacitorFullscreen';
import { cn } from '@/lib/utils';

const badProxiesCache = new Map<string, number>(); 
const PROXY_TIMEOUT_MS = 5 * 60 * 1000; 

const getStoredProxy = (channelId: string): string | null => {
  try {
    return localStorage.getItem(`tvstreamz_best_proxy_${channelId}`);
  } catch {
    return null;
  }
};

const setStoredProxy = (channelId: string, proxyUrl: string) => {
  try {
    if (proxyUrl) {
      localStorage.setItem(`tvstreamz_best_proxy_${channelId}`, proxyUrl);
    } else {
      localStorage.removeItem(`tvstreamz_best_proxy_${channelId}`);
    }
  } catch (e) {
    console.warn('Failed to save proxy to localStorage', e);
  }
};

const getProxyUrls = async (proxyType: string = 'cloudflare'): Promise<{ primary: string; backup: string; backup2: string; backup3: string; backup4: string; backup5: string; backup6: string }> => {
  try {
    const { data } = await supabase.from('site_settings').select('value').eq('key', 'iptv_config').single();
    const config = data?.value as any;
    const prefix = proxyType === 'supabase' ? 'supabase_proxy_url' : 
                   proxyType === 'vercel' ? 'vercel_proxy_url' : 'cloudflare_proxy_url';
    return {
      primary: config?.[prefix] || '',
      backup: config?.[`${prefix}_backup`] || '',
      backup2: config?.[`${prefix}_backup2`] || '',
      backup3: config?.[`${prefix}_backup3`] || '',
      backup4: config?.[`${prefix}_backup4`] || '',
      backup5: config?.[`${prefix}_backup5`] || '',
      backup6: config?.[`${prefix}_backup6`] || '',
    };
  } catch {
    return { primary: '', backup: '', backup2: '', backup3: '', backup4: '', backup5: '', backup6: '' };
  }
};

const buildProxiedUrl = (proxyBase: string, manifestUrl: string, userAgent?: string, referrer?: string): string => {
  const url = new URL(proxyBase);
  url.searchParams.set('url', manifestUrl);
  if (userAgent) url.searchParams.set('ua', userAgent);
  if (referrer) url.searchParams.set('referer', referrer);
  return url.toString();
};

const isIOS = (): boolean => {
  return /iPad|iPhone|iPod/.test(navigator.userAgent) || 
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
};

export const getProxiedLogoUrl = (logo?: string, proxyBase?: string) => {
  if (!logo) return '';
  if (logo.startsWith('https://')) return logo;
  
  const fallbackProxy = `https://images.weserv.nl/?url=${encodeURIComponent(logo)}`;
  
  if (!proxyBase) return fallbackProxy; 
  
  try {
    const url = new URL(proxyBase);
    url.searchParams.set('url', logo);
    return url.toString();
  } catch {
    return fallbackProxy;
  }
};

const getYouTubeId = (url: string) => {
  if (!url) return null;
  
  // Regular YouTube URL / Embed / Short
  const regExp = /^.*(youtu.be\/|v\/|u\/\w\/|embed\/|watch\?v=|\&v=)([^#\&\?]*).*/;
  const match = url.match(regExp);
  if (match && match[2].length === 11 && match[2] !== 'live_stream') {
    return { id: match[2], type: 'video' };
  }
  
  // YouTube Live Stream embed with channel ID
  if (url.includes('embed/live_stream')) {
    const channelMatch = url.match(/channel=([a-zA-Z0-9_-]+)/);
    if (channelMatch) return { id: channelMatch[1], type: 'channel' };
  }

  // YouTube Live URL format (youtube.com/live/VIDEO_ID)
  const liveMatch = url.match(/youtube\.com\/live\/([a-zA-Z0-9_-]{11})/);
  if (liveMatch) return { id: liveMatch[1], type: 'video' };
  
  // YouTube Channel Live format (youtube.com/channel/CHANNEL_ID/live)
  const channelLiveMatch = url.match(/youtube\.com\/channel\/([a-zA-Z0-9_-]+)\/live/);
  if (channelLiveMatch) return { id: channelLiveMatch[1], type: 'channel' };
  
  return null;
};

interface LivePlayerProps {
  channel: Channel;
  onProxyChange?: (label: string) => void;
  className?: string;
}

const PlayerCore = ({ channel, onProxyChange }: LivePlayerProps) => {
  const videoRef = useRef<HTMLVideoElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const hlsRef = useRef<Hls | null>(null);
  const shakaRef = useRef<shaka.Player | null>(null);
  const uiRef = useRef<shaka.ui.Overlay | null>(null);
  
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [iosWarning, setIosWarning] = useState<string | null>(null);
  const [hlsLevels, setHlsLevels] = useState<{ height: number; index: number }[]>([]);
  const [currentLevel, setCurrentLevel] = useState(-1);
  const [showQualityMenu, setShowQualityMenu] = useState(false);
  
  const proxyLabelMapRef = useRef<Map<string, string>>(new Map());
  const shakaLoadingRef = useRef<boolean>(false);
  const currentBestProxyRef = useRef<string>('');

  const [reloadTrigger, setReloadTrigger] = useState(0);
  const [isRefreshing, setIsRefreshing] = useState(false);



  const offlineText = {
    title: "Playback Error",
    message: "The stream could not be loaded. Please try again or choose another channel."
  };

  useEffect(() => {
    setReloadTrigger(0);
    setIsRefreshing(false);
  }, [channel.id]);

  useEffect(() => {
    return setupOrientationFullscreen(containerRef.current, !error && !iosWarning);
  }, [error, iosWarning]);

  const checkIOSCompatibility = useMemo(() => {
    if (!isIOS()) return null;
    if (channel.clearKey || channel.widevineUrl) return 'Hindi supported ang stream na ito sa iPhone/iPad dahil sa DRM restrictions.';
    if (channel.type === 'mpd') return 'Maaaring hindi gumana ang stream na ito sa iPhone/iPad.';
    return null;
  }, [channel]);

  useEffect(() => {
    if (checkIOSCompatibility) setIosWarning(checkIOSCompatibility);
  }, [checkIOSCompatibility]);

  const handleQualityChange = useCallback((levelIndex: number) => {
    if (hlsRef.current) {
      hlsRef.current.currentLevel = levelIndex;
      setCurrentLevel(levelIndex);
    }
    setShowQualityMenu(false);
  }, []);

  useEffect(() => {
    let isMounted = true;

    const loadPlayer = async () => {
      if (!videoRef.current || !containerRef.current) return;
      
      if (shakaLoadingRef.current) return;
      shakaLoadingRef.current = true;
      
      setIsLoading(true);
      setError(null);
      if (reloadTrigger > 0) setIsRefreshing(true);

      try {
        if (uiRef.current) { 
          const oldUi = uiRef.current;
          uiRef.current = null;
          await oldUi.destroy(); 
        }
        if (shakaRef.current) { 
          const oldPlayer = shakaRef.current;
          shakaRef.current = null;
          await oldPlayer.destroy(); 
        }
        if (hlsRef.current) { 
          const oldHls = hlsRef.current;
          hlsRef.current = null;
          oldHls.destroy(); 
        }
      } catch (e) {
        console.warn('Error destroying old player instances', e);
      }

      try {
        let streamUrl = channel.manifestUri;
        const activeType = channel.type;
        const activeUseProxy = channel.useProxy;
        const activeProxyType = channel.proxyType;

        if (channel.tvappSlug) {
          try {
            const projectId = import.meta.env.VITE_SUPABASE_PROJECT_ID;
            let resolveUrl = `https://${projectId}.supabase.co/functions/v1/tvapp-resolver?slug=${encodeURIComponent(channel.tvappSlug)}`;
            if (reloadTrigger > 0) resolveUrl += `&force_refresh=true`;

            const res = await fetch(resolveUrl);
            if (res.ok) {
              const data = await res.json();
              if (data.resolved_url) streamUrl = data.resolved_url;
            }
          } catch (e) {
            console.warn('[TVApp] Failed to resolve slug', e);
          }
        }

        if (!streamUrl) {
          throw new Error('Stream URL could not be resolved or is empty.');
        }

        const defaultUA = "Dalvik/2.1.0 (Linux; U; Android 12; Pixel 6 Build/SD1A.210817.036)";
        const targetUA = channel.userAgent || defaultUA;

        const isStrict = activeProxyType && activeProxyType !== 'none';
        const isAuto = !isStrict && activeUseProxy;
        
        const [cfProxies, sbProxies, vercelProxies] = await Promise.all([
          getProxyUrls('cloudflare').catch(() => ({})),
          getProxyUrls('supabase').catch(() => ({})),
          getProxyUrls('vercel').catch(() => ({}))
        ]);

        let providerProxies: string[] = [];
        const combinedMap = { ...cfProxies, ...sbProxies, ...vercelProxies } as Record<string, string>;
        
        if (isStrict) {
          const preferredProxies = activeProxyType === 'supabase' ? sbProxies : 
                                   activeProxyType === 'vercel' ? vercelProxies : cfProxies;
          
          let preferredUrls: string[] = [];
          if (channel.proxyOrder && channel.proxyOrder.length > 0) {
            preferredUrls = channel.proxyOrder
              .map(key => (preferredProxies as any)[key])
              .filter(p => p && typeof p === 'string');
          } else {
            preferredUrls = Object.values(preferredProxies).filter(p => p && typeof p === 'string');
          }
          providerProxies = [...preferredUrls];
        } else {
          providerProxies = Array.from(new Set([
            ...Object.values(cfProxies),
            ...Object.values(sbProxies),
            ...Object.values(vercelProxies)
          ].filter(p => p && typeof p === 'string'))) as string[];
          
          // Add public proxy as absolute fallback
          if (!providerProxies.includes('https://corsproxy.io/?url=')) {
            providerProxies.push('https://corsproxy.io/?url=');
          }
        }

        const labelMap = new Map<string, string>();
        labelMap.set('direct', 'Direct');
        
        providerProxies.forEach((p, idx) => {
          if (Object.values(cfProxies).includes(p)) {
            const key = Object.keys(cfProxies).find(k => (cfProxies as any)[k] === p);
            labelMap.set(p, key === 'primary' ? 'Cloudflare' : (key ? `CF-${key}` : `Backup ${idx}`));
          } else if (Object.values(sbProxies).includes(p)) {
            const key = Object.keys(sbProxies).find(k => (sbProxies as any)[k] === p);
            labelMap.set(p, key === 'primary' ? 'Supabase' : (key ? `SB-${key}` : `Worker ${idx}`));
          } else {
            const key = Object.keys(vercelProxies).find(k => (vercelProxies as any)[k] === p);
            labelMap.set(p, key === 'primary' ? 'Vercel HLS' : (key ? `VC-${key}` : `Proxy ${idx}`));
          }
        });
        labelMap.set('https://corsproxy.io/?url=', 'Public Proxy');
        proxyLabelMapRef.current = labelMap;

        if (isMounted) onProxyChange?.(isStrict ? `Using ${activeProxyType}...` : 'Detecting best connection...');

        let activeProxyUrl = '';
        
        const testConnection = (proxy: string | null, timeoutMs: number = 6000) => {
          return new Promise<string>(async (resolve, reject) => {
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
            
            const tryFetch = async (url: string) => {
              return fetch(url, { signal: controller.signal, mode: 'cors', credentials: 'omit' });
            };

            try {
              const testUrl = proxy === 'direct' ? streamUrl : buildProxiedUrl(proxy!, streamUrl, targetUA, channel.referrer);
              let res: Response;
              try {
                res = await tryFetch(testUrl);
                if (!res.ok && proxy !== 'direct') {
                  const cleanUrl = buildProxiedUrl(proxy!, streamUrl, targetUA, channel.referrer);
                  const retryRes = await tryFetch(cleanUrl);
                  if (retryRes.ok) res = retryRes;
                }
              } catch (fetchErr) {
                if (proxy !== 'direct') {
                  const cleanUrl = buildProxiedUrl(proxy!, streamUrl, targetUA, channel.referrer);
                  res = await tryFetch(cleanUrl);
                } else {
                  throw fetchErr;
                }
              }

              clearTimeout(timeoutId);
              
              if (res.ok || res.status === 402) {
                resolve(proxy!);
              } else {
                if (proxy !== 'direct' && proxy) badProxiesCache.set(`${channel.id}:${proxy}`, Date.now());
                reject(new Error(`Status ${res.status}`));
              }
            } catch (err) {
              clearTimeout(timeoutId);
              if (proxy !== 'direct' && proxy) badProxiesCache.set(`${channel.id}:${proxy}`, Date.now());
              reject(err);
            }
          });
        };

        const candidates: string[] = [];
        const isPageHttps = window.location.protocol === 'https:';
        const isStreamHttp = streamUrl.startsWith('http:');
        const needsProxyForMixedContent = isPageHttps && isStreamHttp;

        if (!needsProxyForMixedContent && !isStrict) {
          candidates.push('direct');
        }

        candidates.push(...providerProxies.filter(p => {
          const cacheKey = `${channel.id}:${p}`;
          if (badProxiesCache.has(cacheKey)) {
            if (Date.now() - badProxiesCache.get(cacheKey)! < PROXY_TIMEOUT_MS) return false;
            badProxiesCache.delete(cacheKey);
          }
          return true;
        }));
        
        if (candidates.length === 0 && needsProxyForMixedContent) {
          setError("This channel requires HTTPS but only provides HTTP. No proxy is available.");
          setIsLoading(false);
          return;
        }

        try {
          if (isStrict || isAuto) {
            const cachedProxy = getStoredProxy(channel.id);
            let selectionSuccessful = false;

            if (cachedProxy && candidates.includes(cachedProxy)) {
              if (isMounted) onProxyChange?.(`Verifying ${labelMap.get(cachedProxy) || 'Cache'}...`);
              try {
                activeProxyUrl = await testConnection(cachedProxy, 2000);
                selectionSuccessful = true;
                if (isMounted) onProxyChange?.(`${labelMap.get(activeProxyUrl) || 'Connected'} (Verified)`);
              } catch (e) {
                setStoredProxy(channel.id, '');
              }
            }

            if (!selectionSuccessful) {
              if (isMounted) onProxyChange?.('Finding best connection...');
              const raceCandidates = candidates.filter(p => {
                const cacheKey = `${channel.id}:${p}`;
                return !badProxiesCache.has(cacheKey) || (Date.now() - badProxiesCache.get(cacheKey)! >= PROXY_TIMEOUT_MS);
              });

              if (raceCandidates.length > 0) {
                const racePromises = raceCandidates.map(c => testConnection(c));
                activeProxyUrl = await (Promise as any).any(racePromises);
                
                if (activeProxyUrl && activeProxyUrl !== 'direct') {
                  setStoredProxy(channel.id, activeProxyUrl);
                }
              } else {
                throw new Error('No working proxies found');
              }
            }

            if (isMounted) onProxyChange?.(labelMap.get(activeProxyUrl) || 'Connected');
            if (activeProxyUrl === 'direct') activeProxyUrl = ''; 
          } else {
            activeProxyUrl = '';
            if (isMounted) onProxyChange?.('Direct');
          }
        } catch (err) {
          activeProxyUrl = ''; 
          if (isMounted) onProxyChange?.('Fallback');
        }

        currentBestProxyRef.current = activeProxyUrl || combinedMap.primary || '';
        const proxyUrl = activeProxyUrl;

        const configureShakaProxy = (player: shaka.Player, proxyToUse: string) => {
          if (!proxyToUse) return;
          const netEngine = player.getNetworkingEngine();
          if (!netEngine) return;
          
          netEngine.clearAllRequestFilters();
          const manifestBase = streamUrl.substring(0, streamUrl.lastIndexOf('/') + 1);
          const proxyOrigin = new URL(proxyToUse).origin;
          const proxyPathname = new URL(proxyToUse).pathname;
          
          netEngine.registerRequestFilter((type: any, request: any) => {
            request.allowCrossSiteCredentials = false;
            const url = request.uris[0];
            if (!url) return;
            if (!url.startsWith('http')) return;
            if (url.includes('?url=') || url.includes('&url=')) return;
            
            // WIDEVINE FIX: Hayaang direkta ang paghingi ng license key
            if (type === shaka.net.NetworkingEngine.RequestType.LICENSE) {
              return;
            }

            if (url.startsWith(proxyOrigin)) {
              const path = url.substring(proxyOrigin.length);
              let relativePath = path;
              if (proxyPathname !== '/' && relativePath.startsWith(proxyPathname)) {
                relativePath = relativePath.substring(proxyPathname.length);
              }
              relativePath = relativePath.startsWith('/') ? relativePath.substring(1) : relativePath;
              const fullOriginalUrl = manifestBase + relativePath;
              request.uris[0] = buildProxiedUrl(proxyToUse, fullOriginalUrl, targetUA, channel.referrer);
              return;
            }
            request.uris[0] = buildProxiedUrl(proxyToUse, url, targetUA, channel.referrer);
          });
        };

        const triggerAutoRefresh = () => {
          if (channel.tvappSlug && reloadTrigger < 2) { 
            if (isMounted) setReloadTrigger(prev => prev + 1);
            return true;
          }
          return false;
        };

        if (activeType === 'hls') {
          if (channel.widevineUrl) {
            videoRef.current.controls = false;
            shaka.polyfill.installAll();
            
            if (!shaka.Player.isBrowserSupported()) {
              if (isMounted) { setError('Browser unsupported.'); setIsLoading(false); setIsRefreshing(false); }
              return;
            }

            const player = new shaka.Player(/* mediaElement= */ null, containerRef.current);
            await player.attach(videoRef.current);
            shakaRef.current = player;
            const ui = new shaka.ui.Overlay(player, containerRef.current, videoRef.current);
            uiRef.current = ui;
            
            player.configure({ 
              preferredAudioLanguage: 'en',
              preferredTextLanguage: 'en',
              drm: { servers: { 'com.widevine.alpha': channel.widevineUrl } }, 
              abr: { enabled: true },
              offline: { usePersistentLicense: false }
            });
            player.setTextTrackVisibility(true);
            ui.configure({ overflowMenuButtons: ['quality', 'language', 'captions', 'picture_in_picture', 'cast'], addBigPlayButton: true });
            
            configureShakaProxy(player, proxyUrl);

            try {
              await player.load(proxyUrl ? buildProxiedUrl(proxyUrl, streamUrl, targetUA, channel.referrer) : streamUrl);
              if (isMounted) { setIsLoading(false); setIsRefreshing(false); videoRef.current?.play().catch(() => {}); }
            } catch (err) {
              if (isMounted) {
                if (!triggerAutoRefresh()) {
                  setError('Failed to load stream.');
                  setIsLoading(false);
                  setIsRefreshing(false);
                }
              }
            }
          } else {
            videoRef.current.controls = true; 
            if (Hls.isSupported()) {
              const hls = new Hls({ 
                enableWorker: true, 
                lowLatencyMode: true, 
                startLevel: -1,
                fragLoadingMaxRetry: 3,
                manifestLoadingMaxRetry: 3,
                levelLoadingMaxRetry: 3,
                backBufferLength: 60,
                // Make subtitle errors non-fatal
                ignoreDevicePixelRatio: true,
                xhrSetup: (xhr, url) => {
                  if (proxyUrl) {
                    const proxyOrigin = new URL(proxyUrl).origin;
                    if (url.includes('?url=') || url.includes('&url=')) return;

                    if (url.startsWith(proxyOrigin)) {
                       const proxyPathname = new URL(proxyUrl).pathname;
                       let relativePath = url.substring(proxyOrigin.length);
                       if (proxyPathname !== '/' && relativePath.startsWith(proxyPathname)) {
                         relativePath = relativePath.substring(proxyPathname.length);
                       }
                       relativePath = relativePath.startsWith('/') ? relativePath.substring(1) : relativePath;
                       const manifestBase = streamUrl.substring(0, streamUrl.lastIndexOf('/') + 1);
                       const fullOriginalUrl = manifestBase + relativePath;
                       xhr.open('GET', buildProxiedUrl(proxyUrl, fullOriginalUrl, targetUA, channel.referrer), true);
                    } else if (url.startsWith('http')) {
                       xhr.open('GET', buildProxiedUrl(proxyUrl, url, targetUA, channel.referrer), true);
                    }
                  }
                }
              });
              hlsRef.current = hls;
              hls.loadSource(proxyUrl ? buildProxiedUrl(proxyUrl, streamUrl, targetUA, channel.referrer) : streamUrl);
              hls.attachMedia(videoRef.current);
              
              hls.on(Hls.Events.MANIFEST_PARSED, (_, data) => {
                if (isMounted) {
                  setIsLoading(false);
                  setIsRefreshing(false);
                  const levels = hls.levels.map((l, i) => ({ height: l.height, index: i })).filter(l => l.height > 0).sort((a, b) => b.height - a.height);
                  setHlsLevels(levels.filter((l, i, arr) => i === 0 || l.height !== arr[i - 1].height));
                  
                  // Auto-select English subtitles if available
                  const subTracks = hls.subtitleTracks;
                  const enIndex = subTracks.findIndex(t => 
                    t.lang?.toLowerCase().startsWith('en') || 
                    t.name?.toLowerCase().includes('english')
                  );
                  if (enIndex !== -1) {
                    hls.subtitleTrack = enIndex;
                    hls.subtitleDisplay = true;
                  }

                  videoRef.current?.play().catch(() => {});
                }
              });
              
              let currentProxyIndex = candidates.indexOf(proxyUrl || 'direct');
              if (currentProxyIndex === -1) currentProxyIndex = 0;

              hls.on(Hls.Events.ERROR, (_, data) => {
                if (data.fatal && isMounted) {
                  // Handle non-video track errors (like subtitles) gracefully
                  if (data.details === Hls.ErrorDetails.FRAG_LOAD_ERROR || data.details === Hls.ErrorDetails.FRAG_LOAD_TIMEOUT) {
                    if (data.frag && data.frag.type !== 'main' && data.frag.type !== 'video') {
                      console.warn('[LivePlayer] Non-fatal fragment error:', data.details, data.frag.type);
                      return;
                    }
                  }

                  if ((isAuto || isStrict) && proxyUrl && proxyUrl === getStoredProxy(channel.id)) setStoredProxy(channel.id, '');

                  currentProxyIndex++;
                  if ((isAuto || isStrict) && currentProxyIndex < candidates.length) {
                    const nextProxy = candidates[currentProxyIndex];
                    onProxyChange?.(proxyLabelMapRef.current.get(nextProxy) || `Proxy ${currentProxyIndex + 1}`);
                    hls.loadSource(buildProxiedUrl(nextProxy === 'direct' ? '' : nextProxy, streamUrl, targetUA, channel.referrer));
                    return;
                  }
                  
                  if (!triggerAutoRefresh()) {
                    setError('Playback Error');
                    setIsLoading(false);
                    setIsRefreshing(false);
                  }
                }
              });
            } else if (videoRef.current.canPlayType('application/vnd.apple.mpegurl')) {
              videoRef.current.src = proxyUrl ? buildProxiedUrl(proxyUrl, streamUrl, targetUA, channel.referrer) : streamUrl;
              videoRef.current.addEventListener('loadedmetadata', () => {
                if (isMounted) { setIsLoading(false); setIsRefreshing(false); videoRef.current?.play().catch(() => {}); }
              });
            }
          }
        }
        else if (activeType === 'mpd') {
          videoRef.current.controls = false;
          shaka.polyfill.installAll();
          
          if (!shaka.Player.isBrowserSupported()) {
            if (isMounted) { setError('Browser unsupported.'); setIsLoading(false); setIsRefreshing(false); }
            return;
          }

          const player = new shaka.Player(/* mediaElement= */ null, containerRef.current);
          await player.attach(videoRef.current);
          shakaRef.current = player;
          const ui = new shaka.ui.Overlay(player, containerRef.current, videoRef.current);
          uiRef.current = ui;
          
          player.configure({ 
            preferredAudioLanguage: 'en',
            preferredTextLanguage: 'en',
            drm: { clearKeys: channel.clearKey || {}, servers: channel.widevineUrl ? { 'com.widevine.alpha': channel.widevineUrl } : {} },
            offline: { usePersistentLicense: false }
          });
          player.setTextTrackVisibility(true);
          ui.configure({ overflowMenuButtons: ['quality', 'language', 'captions', 'picture_in_picture', 'cast'], addBigPlayButton: true });
          
          configureShakaProxy(player, proxyUrl);

          try {
            await player.load(proxyUrl ? buildProxiedUrl(proxyUrl, streamUrl, targetUA, channel.referrer) : streamUrl);
            if (isMounted) { setIsLoading(false); setIsRefreshing(false); videoRef.current?.play().catch(() => {}); }
          } catch (err) {
            if (proxyUrl && proxyUrl === getStoredProxy(channel.id)) setStoredProxy(channel.id, '');

            let dashRecovered = false;
            if (isAuto || isStrict) {
              let startIndex = candidates.indexOf(proxyUrl || 'direct');
              if (startIndex === -1) startIndex = 0;

              for (let i = startIndex + 1; i < candidates.length; i++) {
                const fallbackProxy = candidates[i];
                const finalFallback = fallbackProxy === 'direct' ? '' : fallbackProxy;
                configureShakaProxy(player, finalFallback);
                try {
                  await player.load(finalFallback ? buildProxiedUrl(finalFallback, streamUrl, targetUA, channel.referrer) : streamUrl);
                  if (isMounted) { setIsLoading(false); setIsRefreshing(false); onProxyChange?.(proxyLabelMapRef.current.get(fallbackProxy) || `Proxy ${i + 1}`); videoRef.current?.play().catch(() => {}); }
                  dashRecovered = true;
                  break;
                } catch (retryErr) {}
              }
            }
            if (!dashRecovered && isMounted) {
              if (!triggerAutoRefresh()) {
                setError('Channel is currently offline.');
                setIsLoading(false);
                setIsRefreshing(false);
              }
            }
          }
        }
        else if (activeType === 'plain') {
          if (videoRef.current) {
            videoRef.current.controls = true;
            const finalUrl = proxyUrl ? buildProxiedUrl(proxyUrl, streamUrl, targetUA, channel.referrer) : streamUrl;
            videoRef.current.src = finalUrl;
            videoRef.current.addEventListener('loadedmetadata', () => {
              if (isMounted) {
                setIsLoading(false);
                setIsRefreshing(false);
                videoRef.current?.play().catch(() => {});
              }
            });
            videoRef.current.addEventListener('error', () => {
              if (isMounted) {
                if (!triggerAutoRefresh()) {
                  setError('Failed to load direct stream.');
                  setIsLoading(false);
                  setIsRefreshing(false);
                }
              }
            });
          }
        }
      } catch (err) {
        if (isMounted) { setError('Failed to initialize player.'); setIsLoading(false); setIsRefreshing(false); }
      }
    };

    loadPlayer().finally(() => {
      shakaLoadingRef.current = false;
    });

    return () => {
      isMounted = false;
    };
  }, [channel, reloadTrigger]);

  return (
    <>
      {/* Loading spinner removed as per user request */}

      {isRefreshing && (
        <div className="absolute inset-0 flex flex-col items-center justify-center bg-card/90 backdrop-blur-sm z-20">
          <RefreshCw className="w-10 h-10 text-primary animate-spin mb-3" />
          <p className="text-primary font-medium">Auto-refreshing stream...</p>
          <p className="text-xs text-muted-foreground mt-1">Getting fresh token</p>
        </div>
      )}

      {iosWarning && (
        <div className="absolute inset-0 flex flex-col items-center justify-center bg-card gap-3 p-4 text-center z-20">
          <Smartphone className="w-12 h-12 text-amber-500" />
          <p className="text-amber-500 font-medium">iOS Compatibility Issue</p>
          <p className="text-muted-foreground text-sm max-w-xs">{iosWarning}</p>
        </div>
      )}

      {error && !iosWarning && (
        <div 
          className="absolute inset-0 flex flex-col items-center justify-center z-20 bg-cover bg-center bg-no-repeat"
          style={{ backgroundImage: "url('/offline-bars.png')" }}
        >
          <div className="absolute inset-0 bg-black/60 backdrop-blur-[2px]"></div>
          
          <div className="relative z-10 flex flex-col items-center gap-3 p-4 text-center">
            <AlertCircle className="w-12 h-12 text-destructive drop-shadow-md" />
            <p className="text-white font-medium drop-shadow-md bg-black/50 px-4 py-2 rounded-lg border border-white/10">
              {offlineText.title}
            </p>
            <p className="text-xs text-gray-300 whitespace-pre-wrap">{offlineText.message}</p>
          </div>
        </div>
      )}

      <div 
        ref={containerRef} 
        className="relative w-full h-full group"
      >
        <video 
          ref={videoRef} 
          className="w-full h-full" 
          autoPlay 
          playsInline 
          onPlaying={() => {
            if (isLoading) setIsLoading(false);
            if (isRefreshing) setIsRefreshing(false);
          }}
        />
        
        {hlsLevels.length > 1 && hlsRef.current && (
          <div className="absolute top-2 right-2 z-30">
            <button onClick={() => setShowQualityMenu(prev => !prev)} className="bg-background/80 backdrop-blur-sm border-2 border-border rounded-lg p-2 hover:bg-accent focus:outline-none focus:ring-2 focus:ring-primary focus:border-primary transition-colors">
              <Settings className="w-6 h-6 text-foreground" />
            </button>
            {showQualityMenu && (
              <div className="absolute top-full right-0 mt-1 bg-popover border border-border rounded-lg shadow-lg overflow-hidden min-w-[140px]">
                <button onClick={() => handleQualityChange(-1)} className={`w-full flex items-center gap-2 px-4 py-3 text-sm hover:bg-accent ${currentLevel === -1 ? 'text-primary font-semibold' : 'text-foreground'}`}>
                  {currentLevel === -1 && <Check className="w-4 h-4" />}<span className={currentLevel === -1 ? '' : 'ml-6'}>Auto</span>
                </button>
                {hlsLevels.map((level) => (
                  <button key={level.index} onClick={() => handleQualityChange(level.index)} className={`w-full flex items-center gap-2 px-4 py-3 text-sm hover:bg-accent ${currentLevel === level.index ? 'text-primary font-semibold' : 'text-foreground'}`}>
                    {currentLevel === level.index && <Check className="w-4 h-4" />}<span className={currentLevel === level.index ? '' : 'ml-6'}>{level.height}p</span>
                  </button>
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </>
  );
};

export const LivePlayer = ({ channel, onProxyChange, className }: LivePlayerProps) => {
  if (channel.type === 'youtube') {
    const yt = getYouTubeId(channel.embedUrl || channel.manifestUri || '');
    return (
      <div className={cn("aspect-video w-full rounded-xl overflow-hidden bg-card border border-border", className)}>
        {yt ? (
          <YouTubePlayer videoId={yt.id} title={channel.name} isChannel={yt.type === 'channel'} />
        ) : (
          <iframe 
            src={`${channel.embedUrl}&autoplay=1`} 
            title={channel.name} 
            className="w-full h-full" 
            allowFullScreen 
            allow="autoplay; encrypted-media" 
          />
        )}
      </div>
    );
  }

  return (
    <div className={cn("aspect-video w-full rounded-xl overflow-hidden bg-card border border-border relative", className)}>
      <PlayerCore key={channel.id} channel={channel} onProxyChange={onProxyChange} />
    </div>
  );
};
