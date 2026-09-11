export function directusErrorMessage(payload, fallbackMessage = 'Request failed', options = {}) {
  const includePayloadMessage = options.includePayloadMessage !== false;
  return payload?.errors?.[0]?.message
    || (includePayloadMessage ? payload?.message : '')
    || fallbackMessage;
}

export async function parseDirectusResponse(response, fallbackMessage, options = {}) {
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(directusErrorMessage(payload, fallbackMessage, options));
  }
  return payload;
}
