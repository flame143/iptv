import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { encode as hexEncode } from "https://deno.land/std@0.177.0/encoding/hex.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { url: targetUrl } = await req.json();

    if (!targetUrl) {
      return new Response(JSON.stringify({ error: 'Missing target URL' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const secretKey = Deno.env.get('SECRET_KEY');
    
    // If no secret key is configured, return empty tokens (graceful fallback)
    if (!secretKey) {
      return new Response(JSON.stringify({ exp: '', sig: '' }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Generate expiration time (e.g., 4 hours from now)
    const expiresInSeconds = 4 * 60 * 60;
    const exp = Math.floor(Date.now() / 1000) + expiresInSeconds;

    // Generate HMAC SHA-256 signature
    const encoder = new TextEncoder();
    const keyData = encoder.encode(secretKey);
    
    const cryptoKey = await crypto.subtle.importKey(
      "raw", 
      keyData, 
      { name: "HMAC", hash: "SHA-256" }, 
      false, 
      ["sign"]
    );

    const dataToSign = encoder.encode(`${targetUrl}:${exp}`);
    const signatureBuffer = await crypto.subtle.sign("HMAC", cryptoKey, dataToSign);
    
    // Convert buffer to hex string
    const hashArray = Array.from(new Uint8Array(signatureBuffer));
    const sig = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

    return new Response(JSON.stringify({ exp: exp.toString(), sig }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
