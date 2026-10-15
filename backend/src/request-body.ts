import { APIError } from "./types";

export const JSON_BODY_LIMIT = 64 * 1024;
export const IMPORT_BODY_LIMIT = 20 * 1024 * 1024;

export async function readBody(request: Request, limit: number): Promise<Uint8Array<ArrayBuffer>> {
  const length = request.headers.get("content-length");
  if (length && (!/^\d+$/.test(length) || Number(length) > limit)) throw new APIError(413, "请求内容过大");
  const reader = request.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) {
        await reader.cancel();
        throw new APIError(413, "请求内容过大");
      }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  return new Uint8Array(Buffer.concat(chunks, size));
}
