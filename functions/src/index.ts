import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging, MulticastMessage } from 'firebase-admin/messaging';
import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';
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

function normalizeVehicleType(value: unknown): string {
  return String(value ?? '').trim().toLocaleLowerCase('ru-RU');
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
  const orderId = event.params.orderId;
  const startedAt = Date.now();
  logger.info('FCM notification flow started', { orderId });

  const orderSnapshot = event.data;
  if (!orderSnapshot) {
    logger.warn('FCM notification skipped: document snapshot is missing', { orderId });
    return;
  }

  const order = orderSnapshot.data();
  if (order.status !== 'active') {
    logger.info('FCM notification skipped: order is not active', { orderId, status: order.status ?? null });
    return;
  }

  const orderLat = asNumber(order.lat);
  const orderLon = asNumber(order.lon);
  const orderVehicleType = normalizeVehicleType(order.vehicleType ?? order.type);
  if (!orderVehicleType) {
    logger.warn('FCM notification skipped: order has no vehicle type', { orderId });
    return;
  }
  if (orderLat === null || orderLon === null) {
    logger.warn('FCM notification skipped: order has no valid coordinates', { orderId });
    return;
  }

  const driversSnapshot = await db.collection('drivers').where('isOnline', '==', true).get();
  const tokens: string[] = [];
  const selectionDetails: Array<Record<string, unknown>> = [];
  let driversWithoutLocation = 0;
  let driversWithoutToken = 0;
  let driversWithDifferentVehicleType = 0;
  let nearbyDrivers = 0;

  for (const driver of driversSnapshot.docs) {
    const data = driver.data();
    const driverLat = asNumber(data.lat);
    const driverLon = asNumber(data.lon);
    const token = typeof data.fcmToken === 'string' ? data.fcmToken : null;
    const candidate = {
      uid: driver.id,
      vehicleType: data.vehicleType ?? null,
      distanceKm: null as number | null,
      hasLocation: driverLat !== null && driverLon !== null,
      hasToken: Boolean(token),
      selected: false,
      reason: '',
    };
    if (normalizeVehicleType(data.vehicleType) !== orderVehicleType) {
      driversWithDifferentVehicleType += 1;
      candidate.reason = 'vehicle_type_mismatch';
      selectionDetails.push(candidate);
      continue;
    }
    if (driverLat === null || driverLon === null) {
      driversWithoutLocation += 1;
      candidate.reason = 'missing_location';
      selectionDetails.push(candidate);
      continue;
    }
    if (!token) {
      driversWithoutToken += 1;
      candidate.distanceKm = distanceKm(orderLat, orderLon, driverLat, driverLon);
      candidate.reason = 'missing_token';
      selectionDetails.push(candidate);
      continue;
    }

    const driverDistanceKm = distanceKm(orderLat, orderLon, driverLat, driverLon);
    candidate.distanceKm = driverDistanceKm;
    if (driverDistanceKm <= notificationRadiusKm) {
      nearbyDrivers += 1;
      tokens.push(token);
      candidate.selected = true;
      candidate.reason = 'selected';
    } else {
      candidate.reason = 'outside_radius';
    }
    selectionDetails.push(candidate);
  }

  const uniqueTokens = [...new Set(tokens)];
  logger.info('FCM recipient selection completed', {
    orderId,
    onlineDrivers: driversSnapshot.size,
    nearbyDrivers,
    uniqueRecipients: uniqueTokens.length,
    driversWithoutLocation,
    driversWithoutToken,
    driversWithDifferentVehicleType,
    orderVehicleType,
    radiusKm: notificationRadiusKm,
  });

  if (uniqueTokens.length === 0) {
    logger.info('FCM notification not sent: no nearby drivers with valid tokens', { orderId });
    await db.collection('_notificationDispatches').doc(orderId).set({
      orderId,
      recipients: 0,
      successCount: 0,
      failureCount: 0,
      radiusKm: notificationRadiusKm,
      candidateDetails: selectionDetails,
      failureCodes: ['no_recipients'],
      createdAt: new Date().toISOString(),
    });
    return;
  }

  if (process.env.FCM_DRY_RUN === 'true') {
    await db.collection('_emulatorDispatches').doc(orderId).set({
      orderId,
      tokens: uniqueTokens,
      radiusKm: notificationRadiusKm,
      createdAt: new Date().toISOString(),
    });
    logger.info('FCM dry-run dispatch recorded', { orderId, recipients: uniqueTokens.length, durationMs: Date.now() - startedAt });
    return;
  }

  const type = String(order.type ?? 'Спецтехника');
  const address = String(order.address ?? 'Новая заявка');
  const batches = chunks(uniqueTokens, 500).map((tokenChunk) => ({
    tokens: tokenChunk,
    message: {
      tokens: tokenChunk,
      notification: {
        title: 'Новая заявка рядом',
        body: `${type} · ${address}`,
      },
      data: {
        orderId,
        type,
        address,
        lat: String(orderLat),
        lon: String(orderLon),
        status: 'active',
      },
        android: {
          priority: 'high',
          notification: {
            channelId: 'order_alerts',
            sound: 'order_alert',
          },
      },
    },
  }));

  const batchResults = await Promise.all(batches.map(async (batch, batchIndex) => {
    try {
      const result = await getMessaging().sendEachForMulticast(batch.message as MulticastMessage);
      const failures = result.responses
        .map((response, responseIndex) => ({ response, responseIndex }))
        .filter(({ response }) => !response.success)
        .map(({ response, responseIndex }) => ({
          batchIndex,
          recipientIndex: batchIndex * 500 + responseIndex,
          code: response.error?.code ?? 'unknown',
          message: response.error?.message ?? 'Unknown FCM error',
        }));

      logger.info('FCM batch completed', {
        orderId,
        batchIndex,
        batchRecipients: batch.tokens.length,
        successCount: result.successCount,
        failureCount: result.failureCount,
        failureDetails: failures,
      });
      return { successCount: result.successCount, failureCount: result.failureCount, failures };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error('FCM batch request failed', { orderId, batchIndex, batchRecipients: batch.tokens.length, error: message });
      return { successCount: 0, failureCount: batch.tokens.length, failures: [{ batchIndex, code: 'batch_request_failed', message }] };
    }
  }));

  const successCount = batchResults.reduce((total, result) => total + result.successCount, 0);
  const failureCount = batchResults.reduce((total, result) => total + result.failureCount, 0);
  const failureDetails = batchResults.flatMap((result) => result.failures);
  const dispatchSummary = {
    orderId,
    recipients: uniqueTokens.length,
    successCount,
    failureCount,
    radiusKm: notificationRadiusKm,
    durationMs: Date.now() - startedAt,
    failureCodes: failureDetails.map((failure) => failure.code),
    candidateDetails: selectionDetails,
    createdAt: new Date().toISOString(),
  };
  logger.info('FCM notification flow completed', dispatchSummary);
  await db.collection('_notificationDispatches').doc(orderId).set(dispatchSummary);
});

export const notifyDriverVerificationStatus = onDocumentUpdated('drivers/{driverId}', async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  const driverId = event.params.driverId;
  if (!before || !after) return;

  const beforeStatus = normalizeVehicleType(before.verificationStatus);
  const afterStatus = normalizeVehicleType(after.verificationStatus);
  const becameVerified = before.isVerified !== true && after.isVerified === true;
  const statusChanged = beforeStatus !== afterStatus && ['approved', 'rejected'].includes(afterStatus);
  if (!becameVerified && !statusChanged) return;

  const token = typeof after.fcmToken === 'string' ? after.fcmToken : null;
  if (!token) {
    logger.warn('Verification notification skipped: driver has no FCM token', { driverId, status: afterStatus });
    return;
  }

  const approved = becameVerified || afterStatus === 'approved';
  const title = approved ? 'Профиль одобрен' : 'Нужны уточнения по профилю';
  const body = approved
    ? 'Регистрация прошла модерацию. Откройте приложение и начинайте принимать заказы.'
    : 'Профиль не прошёл проверку. Свяжитесь со службой поддержки для исправления данных.';

  try {
    const result = await getMessaging().send({
      token,
      notification: { title, body },
      data: {
        type: 'verification_status',
        status: approved ? 'approved' : 'rejected',
        driverId,
      },
      android: {
        priority: 'high',
        notification: { channelId: 'order_alerts', sound: 'default' },
      },
    });
    logger.info('Verification notification sent', { driverId, status: approved ? 'approved' : 'rejected', messageId: result });
  } catch (error) {
    logger.error('Verification notification failed', {
      driverId,
      status: approved ? 'approved' : 'rejected',
      error: error instanceof Error ? error.message : String(error),
    });
  }
});
