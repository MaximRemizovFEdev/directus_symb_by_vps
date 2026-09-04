self.addEventListener('push', (event) => {
  let payload = {};

  try {
    payload = event.data ? event.data.json() : {};
  } catch {
    payload = {
      title: '\u0421\u0438\u043c\u0432\u043e\u043b\u0438\u043a\u0430',
      body: event.data ? event.data.text() : '',
    };
  }

  const title = payload.title || '\u0421\u0438\u043c\u0432\u043e\u043b\u0438\u043a\u0430';
  const options = {
    body: payload.body || '',
    icon: payload.icon || '/admin/favicon.ico',
    badge: payload.badge || '/admin/favicon.ico',
    tag: payload.tag || undefined,
    renotify: true,
    data: {
      url: payload.url || '/admin',
    },
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const targetUrl = new URL(event.notification.data?.url || '/admin', self.location.origin).href;

  event.waitUntil((async () => {
    const windows = await clients.matchAll({ type: 'window', includeUncontrolled: true });

    for (const client of windows) {
      if ('focus' in client && client.url.startsWith(self.location.origin)) {
        await client.focus();
        if ('navigate' in client) return client.navigate(targetUrl);
        return;
      }
    }

    if (clients.openWindow) return clients.openWindow(targetUrl);
  })());
});
