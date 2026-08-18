const youtubeMusicOrigin = 'https://music.youtube.com';
const youtubeMusicPath = '/youtubei/v1/';

function corsHeaders(request) {
  return {
    'Access-Control-Allow-Origin': request.headers.get('Origin') ?? '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers':
      request.headers.get('Access-Control-Request-Headers') ??
      'content-type, accept, accept-language',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin, Access-Control-Request-Headers',
  };
}

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const headers = corsHeaders(request);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers });
    }

    if (request.method !== 'POST' || !url.pathname.startsWith(youtubeMusicPath)) {
      return new Response('Not found', { status: 404, headers });
    }

    const target = new URL(url.pathname + url.search, youtubeMusicOrigin);
    const upstreamHeaders = new Headers({
      Accept: request.headers.get('Accept') ?? '*/*',
      'Accept-Language': request.headers.get('Accept-Language') ?? 'en-US,en;q=0.9',
      'Content-Type': request.headers.get('Content-Type') ?? 'application/json',
      Origin: youtubeMusicOrigin,
      Referer: `${youtubeMusicOrigin}/`,
    });
    const visitorId = request.headers.get('X-Goog-Visitor-Id');
    if (visitorId) upstreamHeaders.set('X-Goog-Visitor-Id', visitorId);

    const upstream = await fetch(target, {
      method: 'POST',
      headers: upstreamHeaders,
      body: request.body,
    });
    const responseHeaders = new Headers(upstream.headers);
    for (const [name, value] of Object.entries(headers)) {
      responseHeaders.set(name, value);
    }
    return new Response(upstream.body, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers: responseHeaders,
    });
  },
};
