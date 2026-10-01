import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging, MulticastMessage } from 'firebase-admin/messaging';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';

if (getApps().length === 0) initializeApp();

const db = getFirestore();
const notificationRadiusKm = Number(process.env.ORDER_NOTIFICATION_RADIUS_KM ?? 5);

function asNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function distanceKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const earthRadiusKm = 6371;
  const toRadians = (degrees: number) => (degrees * Math.PI) / 180;
  const deltaLat = toRadians(lat2 - lat1);
  const deltaLon = toRadians(lon2 - lon1);
  const a = Math.sin(deltaLat / 2) ** 2
    + Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) * Math.sin(deltaLon / 2) ** 2;
  return earthRadiusKm * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function chunks<T>(items: T[], size: number): T[][] {
  const result: T[][] = [];
  for (let index = 0; index < items.length; index += size) result.push(items.slice(index, index + size));
  return result;
}

export const notifyNearbyDrivers = onDocumentCreated('orders/{orderId}', async (event) => {
  const orderSnapshot = event.data;
  if (!orderSnapshot) return;

  const order = orderSnapshot.data();
  if (order.status !== 'active') return;

  const orderLat = asNumber(order.lat);
  const orderLon = asNumber(order.lon);
  if (orderLat === null || orderLon === null) {
    logger.warn('Order has no valid coordinates', { orderId: event.params.orderId });
    return;
  }

  const driversSnapshot = await db.collection('drivers').where('isOnline', '==', true).get();
  const tokens: string[] = [];

  for (const driver of driversSnapshot.docs) {
    const data = driver.data();
    const driverLat = asNumber(data.lat);
    const driverLon = asNumber(data.lon);
    const token = typeof data.fcmToken === 'string' ? data.fcmToken : null;
    if (driverLat === null || driverLon === null || !token) continue;

    if (distanceKm(orderLat, orderLon, driverLat, driverLon) <= notificationRadiusKm) {
      tokens.push(token);
    }
  }

  if (tokens.length === 0) {
    logger.info('No nearby drivers with FCM tokens', { orderId: event.params.orderId });
    return;
  }

  const type = String(order.type ?? 'Спецтехника');
  const address = String(order.address ?? 'Новая заявка');
  const messages: MulticastMessage[] = chunks([...new Set(tokens)], 500).map((tokenChunk) => ({
    tokens: tokenChunk,
    notification: {
      title: 'Новая заявка рядом',
      body: `${type} · ${address}`,
    },
    data: {
      orderId: event.params.orderId,
      type,
      address,
      lat: String(orderLat),
      lon: String(orderLon),
      status: 'active',
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'orders',
        sound: 'default',
      },
    },
  }));

  const results = await Promise.all(messages.map((message) => getMessaging().sendEachForMulticast(message)));
  const successCount = results.reduce((total, result) => total + result.successCount, 0);
  const failureCount = results.reduce((total, result) => total + result.failureCount, 0);
  logger.info('Nearby driver notifications sent', {
    orderId: event.params.orderId,
    recipients: tokens.length,
    successCount,
    failureCount,
    radiusKm: notificationRadiusKm,
  });
});
