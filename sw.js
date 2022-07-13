importScripts('https://g.alicdn.com/kg/workbox/3.3.0/workbox-sw.js');
workbox.setConfig({ modulePathPrefix: 'https://g.alicdn.com/kg/workbox/3.3.0/' });

self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.keys().then(function (names) {
      var validSets = ["is-sw-f8e1ec","is-html-f8e1ec","is-jsdelivr-f8e1ec","is-gtm-f8e1ec","is-gravatar-f8e1ec","is-theme-f8e1ec","is-cdn-f8e1ec","is-json-f8e1ec"];
      return Promise.all(
        names
          .filter(function (name) { return !~validSets.indexOf(name); })
          .map(function (name) {
            indexedDB && indexedDB.deleteDatabase(name);
            return caches.delete(name);
          })
      ).then(function() { self.skipWaiting() });
    })
  );
});

workbox.routing.registerRoute(new RegExp('sw\\.js'), workbox.strategies.networkOnly({
  cacheName: 'is-sw-f8e1ec',
}));
workbox.routing.registerRoute(new RegExp('https://cdn\\.jsdelivr\\.net'), workbox.strategies.staleWhileRevalidate({
  cacheName: 'is-jsdelivr-f8e1ec',
  plugins: [ new workbox.expiration.Plugin({ maxAgeSeconds: 14400 }) ],
}));
workbox.routing.registerRoute(new RegExp('https://www\\.googletagmanager\\.com\?id=.*'), workbox.strategies.staleWhileRevalidate({
  cacheName: 'is-gtm-f8e1ec',
  plugins: [ new workbox.expiration.Plugin({ maxAgeSeconds: 14400 }) ],
}));
workbox.routing.registerRoute(new RegExp('https://www\\.gravatar\\.com'), workbox.strategies.staleWhileRevalidate({
  cacheName: 'is-gravatar-f8e1ec',
  plugins: [ new workbox.expiration.Plugin({ maxAgeSeconds: 14400 }) ],
}));
workbox.routing.registerRoute(new RegExp('/.*\\.(?:js|css|woff2|png|jpg|gif)$'), workbox.strategies.staleWhileRevalidate({
  cacheName: 'is-theme-f8e1ec',
  plugins: [ new workbox.expiration.Plugin({ maxAgeSeconds: 14400 }) ],
}));
workbox.routing.registerRoute(new RegExp('https://cdn\\.yourdomain\\.com'), workbox.strategies.staleWhileRevalidate({
  cacheName: 'is-cdn-f8e1ec',
  plugins: [ new workbox.expiration.Plugin({ maxAgeSeconds: 14400 }) ],
}));
workbox.routing.registerRoute(new RegExp('your_data_prefix/.*\\.json'), workbox.strategies.cacheFirst({
  cacheName: 'is-json-f8e1ec',
  plugins: [ new workbox.expiration.Plugin({ maxAgeSeconds: 14400 }) ],
}));

workbox.routing.registerRoute(new RegExp('/.*(:?/[^\\.]*/?)$'), function(context) {
  var url = context.url.pathname;
  if (!url.endsWith('/')) url += '/';
  return fetch(url);
});