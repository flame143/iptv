import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { Navbar } from "@/components/Navbar";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import { BarChart3, Eye, Users, TrendingUp, Calendar, Film, Tv, MessageSquare, ExternalLink, Wifi, Bell, Mail, LayoutGrid, ChevronLeft, Rocket, Globe, RefreshCw } from "lucide-react";
import { format, subDays } from "date-fns";
import { ChannelManager } from "@/components/admin/ChannelManager";
import { WelcomePopupSettings } from "@/components/admin/WelcomePopupSettings";
import { PagePopupSettings } from "@/components/admin/PagePopupSettings";
import { IptvSettings } from "@/components/admin/IptvSettings";
import { NotificationManager } from "@/components/admin/NotificationManager";
import { MessageManager } from "@/components/admin/MessageManager";
import { AppUpdateManager } from "@/components/admin/AppUpdateManager";
import { SiteSettingsManager } from "@/components/admin/SiteSettingsManager";

interface DailyStats {
  date: string;
  views: number;
  visitors: number;
}

interface ContentStats {
  title: string;
  type: string;
  count: number;
}

interface PageStats {
  path: string;
  count: number;
}

export default function AdminDashboard() {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [isAdmin, setIsAdmin] = useState(false);
  const [activeView, setActiveView] = useState<string>('menu');

  const [dailyStats, setDailyStats] = useState<DailyStats[]>([]);
  const [topContent, setTopContent] = useState<ContentStats[]>([]);
  const [topPages, setTopPages] = useState<PageStats[]>([]);
  const [totals, setTotals] = useState({
    totalViews: 0,
    todayViews: 0,
    uniqueVisitors: 0,
    weeklyVisitors: 0,
  });

  useEffect(() => {
    checkAdminAndLoadData();
  }, []);

  const checkAdminAndLoadData = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser();

      if (!user) {
        navigate("/auth");
        return;
      }

      const { data: roles, error: rolesError } = await supabase
        .from("user_roles")
        .select("role")
        .eq("user_id", user.id)
        .eq("role", "admin");

      if (rolesError || !roles || roles.length === 0) {
        navigate("/auth");
        return;
      }

      setIsAdmin(true);

      try {
        await loadAnalytics();
      } catch (analyticsError) {
        console.error("Error loading analytics:", analyticsError);
      }
    } catch (error) {
      console.error("Error checking admin status:", error);
      navigate("/auth");
    } finally {
      setLoading(false);
    }
  };

  const loadAnalytics = async () => {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const last7Days = subDays(today, 7);
    const last30Days = subDays(today, 30);

    // Get total views
    const { count: totalViews } = await supabase
      .from("site_analytics")
      .select("*", { count: "exact", head: true });

    // Get today's views
    const { count: todayViews } = await supabase
      .from("site_analytics")
      .select("*", { count: "exact", head: true })
      .gte("created_at", today.toISOString());

    // Get unique visitors
    const { data: allVisitors } = await supabase
      .from("site_analytics")
      .select("visitor_id");
    const uniqueVisitors = new Set(allVisitors?.map((v) => v.visitor_id)).size;

    // Get weekly visitors
    const { data: weekVisitors } = await supabase
      .from("site_analytics")
      .select("visitor_id")
      .gte("created_at", last7Days.toISOString());
    const weeklyVisitors = new Set(weekVisitors?.map((v) => v.visitor_id)).size;

    setTotals({
      totalViews: totalViews || 0,
      todayViews: todayViews || 0,
      uniqueVisitors,
      weeklyVisitors,
    });

    const { data: dailyData } = await supabase.rpc('get_daily_analytics_stats', { days_back: 30 });
    const dailyStatsArray: DailyStats[] = (dailyData || []).map((item: { stat_date: string; view_count: number; visitor_count: number }) => ({
      date: format(new Date(item.stat_date), "MMM dd"),
      views: Number(item.view_count),
      visitors: Number(item.visitor_count),
    }));
    setDailyStats(dailyStatsArray);

    const { data: contentData } = await supabase.from("site_analytics").select("content_title, content_type").not("content_id", "is", null).limit(500);
    const contentMap = new Map<string, { type: string; count: number }>();
    contentData?.forEach((item) => {
      if (item.content_title) {
        const key = item.content_title;
        if (!contentMap.has(key)) {
          contentMap.set(key, { type: item.content_type || "movie", count: 0 });
        }
        contentMap.get(key)!.count++;
      }
    });
    const topContentArray: ContentStats[] = [];
    contentMap.forEach((value, key) => { topContentArray.push({ title: key, type: value.type, count: value.count }); });
    topContentArray.sort((a, b) => b.count - a.count);
    setTopContent(topContentArray.slice(0, 10));

    const { data: pageData } = await supabase.from("site_analytics").select("page_path").limit(500);
    const pageMap = new Map<string, number>();
    pageData?.forEach((item) => { pageMap.set(item.page_path, (pageMap.get(item.page_path) || 0) + 1); });
    const topPagesArray: PageStats[] = [];
    pageMap.forEach((count, path) => { topPagesArray.push({ path, count }); });
    topPagesArray.sort((a, b) => b.count - a.count);
    setTopPages(topPagesArray.slice(0, 5));
  };

  // Menu Configuration
  const adminPages = [
    { id: 'channels', title: 'Manage Channels', icon: Tv, desc: 'Add, update, or edit TV channels and stream parameters', color: 'text-purple-500', bg: 'bg-purple-500/10', border: 'border-purple-500/20' },
    { id: 'iptv', title: 'IPTV Settings', icon: Wifi, desc: 'Configure M3U playlists, sources, and playlist synchronizations', color: 'text-[#00FF00]', bg: 'bg-[#00FF00]/10', border: 'border-[#00FF00]/20' },
  ];

  if (loading) {
    return (
      <div className="min-h-screen bg-background">
        <Navbar />
        <div className="container mx-auto px-4 pt-24 pb-8">
          <Skeleton className="h-10 w-64 mb-8" />
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6 max-w-4xl mx-auto mb-8">
            {[...Array(2)].map((_, i) => ( <Skeleton key={i} className="h-48 rounded-2xl" /> ))}
          </div>
        </div>
      </div>
    );
  }

  if (!isAdmin) return null;

  return (
    <div className="min-h-screen bg-background">
      <Navbar />
      <div className="container mx-auto px-4 pt-28 pb-12">
        
        {/* Dynamic Header */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-12 max-w-4xl mx-auto">
          <div className="flex items-center gap-3">
            <div className="p-2.5 bg-primary/10 rounded-xl">
              <BarChart3 className="h-7 w-7 text-primary" />
            </div>
            <div>
              <h1 className="text-2xl sm:text-3xl font-bold text-foreground">Admin Center</h1>
              <p className="text-sm text-muted-foreground">Manage your live TV streaming platform</p>
            </div>
          </div>
          
          {activeView !== 'menu' && (
            <Button variant="outline" onClick={() => setActiveView('menu')} className="gap-2 shadow-sm hover:bg-primary/5">
              <ChevronLeft className="w-4 h-4" /> Back to Menu
            </Button>
          )}
        </div>

        {activeView === 'menu' ? (
          <div className="space-y-8 animate-in fade-in zoom-in-95 duration-300">
            {/* Grid Box Menu */}
            <div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6 max-w-4xl mx-auto">
                {adminPages.map((page) => (
                  <button
                    key={page.id}
                    onClick={() => setActiveView(page.id)}
                    className={`flex flex-col text-left p-6 rounded-2xl border ${page.border} bg-card hover:shadow-md hover:border-primary/50 transition-all duration-200 group relative overflow-hidden`}
                  >
                    <div className={`p-4 rounded-xl ${page.bg} ${page.color} w-fit mb-4 group-hover:scale-110 transition-transform duration-200`}>
                      <page.icon className="w-8 h-8" />
                    </div>
                    <h3 className="font-bold text-xl mb-2 group-hover:text-primary transition-colors">{page.title}</h3>
                    <p className="text-sm text-muted-foreground">{page.desc}</p>
                  </button>
                ))}
              </div>
            </div>
          </div>
        ) : (
          /* RENDER ACTIVE COMPONENT BASED ON SELECTION */
          <div className="animate-in slide-in-from-right-4 duration-300">
            {activeView === 'messages' && <MessageManager />}
            {activeView === 'channels' && <ChannelManager />}
            {activeView === 'settings' && <WelcomePopupSettings />}
            {activeView === 'page-popups' && <PagePopupSettings />}
            {activeView === 'iptv' && <IptvSettings />}
            {activeView === 'notifications' && <NotificationManager />}
            {activeView === 'app-update' && <AppUpdateManager />}
 {activeView === 'site-settings' && <SiteSettingsManager />}
            
            {activeView === 'analytics' && (
              <div className="space-y-6">
                <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
                  <Card className="bg-card border-border">
                    <CardHeader>
                      <CardTitle className="text-foreground flex items-center gap-2">
                        <Eye className="h-5 w-5" />
                        Views Trend {dailyStats.length > 0 && `(${dailyStats[0]?.date} - ${dailyStats[dailyStats.length - 1]?.date})`}
                      </CardTitle>
                    </CardHeader>
                    <CardContent>
                      <div className="h-72 overflow-y-auto pr-2 space-y-2 scrollbar-thin scrollbar-thumb-muted scrollbar-track-transparent">
                        {dailyStats.length === 0 ? ( <p className="text-muted-foreground text-sm">No data yet</p> ) : (
                          dailyStats.slice().reverse().map((stat, index) => (
                            <div key={index} className="flex items-center justify-between p-2 rounded-lg bg-muted/50">
                              <span className="text-sm font-medium text-foreground">{stat.date}</span>
                              <span className="text-sm font-bold text-primary">{stat.views.toLocaleString()} views</span>
                            </div>
                          ))
                        )}
                      </div>
                    </CardContent>
                  </Card>

                  <Card className="bg-card border-border">
                    <CardHeader>
                      <CardTitle className="text-foreground flex items-center gap-2">
                        <Users className="h-5 w-5" />
                        Daily Visitors {dailyStats.length > 0 && `(${dailyStats[0]?.date} - ${dailyStats[dailyStats.length - 1]?.date})`}
                      </CardTitle>
                    </CardHeader>
                    <CardContent>
                      <div className="h-72 overflow-y-auto pr-2 space-y-2 scrollbar-thin scrollbar-thumb-muted scrollbar-track-transparent">
                        {dailyStats.length === 0 ? ( <p className="text-muted-foreground text-sm">No data yet</p> ) : (
                          dailyStats.slice().reverse().map((stat, index) => (
                            <div key={index} className="flex items-center justify-between p-2 rounded-lg bg-muted/50">
                              <span className="text-sm font-medium text-foreground">{stat.date}</span>
                              <span className="text-sm font-bold text-primary">{stat.visitors.toLocaleString()} visitors</span>
                            </div>
                          ))
                        )}
                      </div>
                    </CardContent>
                  </Card>
                </div>

                <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                  <Card className="bg-card border-border">
                    <CardHeader>
                      <CardTitle className="flex items-center gap-2 text-foreground">
                        <Film className="h-5 w-5" /> Top Content
                      </CardTitle>
                    </CardHeader>
                    <CardContent>
                      <div className="space-y-3">
                        {topContent.length === 0 ? ( <p className="text-muted-foreground text-sm">No content views yet</p> ) : (
                          topContent.map((item, index) => (
                            <div key={index} className="flex items-center justify-between p-3 rounded-lg bg-muted/50">
                              <div className="flex items-center gap-3">
                                <span className="text-lg font-bold text-primary">#{index + 1}</span>
                                <div>
                                  <p className="font-medium text-foreground line-clamp-1">{item.title}</p>
                                  <p className="text-xs text-muted-foreground capitalize">{item.type}</p>
                                </div>
                              </div>
                              <span className="font-bold text-foreground">{item.count} views</span>
                            </div>
                          ))
                        )}
                      </div>
                    </CardContent>
                  </Card>

                  <Card className="bg-card border-border">
                    <CardHeader>
                      <CardTitle className="text-foreground">Top Pages</CardTitle>
                    </CardHeader>
                    <CardContent>
                      <div className="space-y-3">
                        {topPages.length === 0 ? ( <p className="text-muted-foreground text-sm">No page views yet</p> ) : (
                          topPages.map((page, index) => (
                            <div key={index} className="flex items-center justify-between p-3 rounded-lg bg-muted/50">
                              <div className="flex items-center gap-3">
                                <span className="text-lg font-bold text-primary">#{index + 1}</span>
                                <p className="font-medium text-foreground">{page.path}</p>
                              </div>
                              <span className="font-bold text-foreground">{page.count} views</span>
                            </div>
                          ))
                        )}
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
