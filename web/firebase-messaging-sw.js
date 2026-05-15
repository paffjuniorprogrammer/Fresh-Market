// Import the Firebase scripts from the CDN
importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-messaging-compat.js');

// Initialize the Firebase app in the service worker by passing in the
// messagingSenderId.
firebase.initializeApp({
  apiKey: "AIzaSyAyXcvufbiAIAyHBZwI3-QLELNDt1VdYe8",
  authDomain: "potato-dashboard-fcm-777666.firebaseapp.com",
  projectId: "potato-dashboard-fcm-777666",
  storageBucket: "potato-dashboard-fcm-777666.firebasestorage.app",
  messagingSenderId: "351902567984",
  appId: "1:351902567984:web:0b0e474a8c42b4b8e327f5"
});

// Retrieve an instance of Firebase Messaging so that it can handle background
// messages.
const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  // Customize notification here
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: '/icons/Icon-192.png'
  };

  return self.registration.showNotification(notificationTitle,
    notificationOptions);
});
