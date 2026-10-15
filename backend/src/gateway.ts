import type { Config } from "./config";
import { APIError, object, text } from "./types";

export interface TimedWord { text: string; offsetMilliseconds: number; durationMilliseconds: number }
export interface AIProvider {
  structured(system: string, user: string, name: string, schema: unknown, signal?: AbortSignal): Promise<unknown>;
  image(prompt: string, signal?: AbortSignal): Promise<Uint8Array>;
  speech(text: string, voice: string, instructions: string, signal?: AbortSignal): Promise<Uint8Array>;
  transcribe(wav: Uint8Array, signal?: AbortSignal): Promise<TimedWord[]>;
}
export class Gateway implements AIProvider {
  constructor(private config: Config) {}
  private async post(path: string, body: unknown, headers: Record<string, string> = {}, signal?: AbortSignal): Promise<Record<string, unknown>> {
    const response = await fetch(this.config.gatewayURL + path, {
      method: "POST", headers: { Authorization: `Bearer ${this.config.gatewayKey}`, "Content-Type": "application/json", ...headers },
      body: JSON.stringify(body), signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(600000)]) : AbortSignal.timeout(600000),
    });
    if (!response.ok) {
      await response.body?.cancel();
      throw new APIError(502, `AI 服务请求失败（${response.status}）`);
    }
    return object(await response.json());
  }
  async structured(system: string, user: string, name: string, schema: unknown, signal?: AbortSignal): Promise<unknown> {
    const response = await this.post("/v1/chat/completions", {
      model: this.config.models.text, messages: [{ role: "system", content: system }, { role: "user", content: user }],
      response_format: { type: "json_schema", json_schema: { name, strict: true, schema } }, reasoning: { effort: "low" },
    }, {}, signal);
    const choices = response.choices as { message?: { content?: string } }[] | undefined;
    const content = choices?.[0]?.message?.content;
    if (typeof content !== "string") throw new APIError(502, "AI 没有返回内容");
    try { return JSON.parse(content.trim().replace(/^```(?:json)?\s*/, "").replace(/\s*```$/, "")); }
    catch { throw new APIError(502, "无法解析 AI 返回的数据"); }
  }
  async image(prompt: string, signal?: AbortSignal): Promise<Uint8Array> {
    const response = await this.post("/v1/images/generations", { model: this.config.models.image, prompt, n: 1, size: "1536x1024", quality: "medium" }, {}, signal);
    const item = (response.data as { b64_json?: string; url?: string }[] | undefined)?.[0];
    if (item?.b64_json) return Buffer.from(text(item.b64_json, "image", 48000000), "base64");
    if (item?.url) {
      const url = new URL(item.url);
      if (url.protocol !== "https:") throw new APIError(502, "AI 返回的图片地址无效");
      const image = await fetch(url, { signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(60000)]) : AbortSignal.timeout(60000) });
      if (!image.ok) throw new APIError(502, "无法下载封面");
      const bytes = new Uint8Array(await image.arrayBuffer());
      if (bytes.length > 32000000) throw new APIError(502, "封面文件过大");
      return bytes;
    }
    throw new APIError(502, "AI 没有返回封面");
  }
  async speech(input: string, voice: string, instructions: string, signal?: AbortSignal): Promise<Uint8Array> {
    const response = await this.post("/v4/ai/speech-model", { text: input, voice, outputFormat: "wav", instructions }, {
      "ai-gateway-protocol-version": "0.0.1", "ai-speech-model-specification-version": "4", "ai-model-id": this.config.models.speech,
    }, signal);
    return Buffer.from(text(response.audio, "audio", 128000000, false), "base64");
  }
  async transcribe(wav: Uint8Array, signal?: AbortSignal): Promise<TimedWord[]> {
    const response = await this.post("/v4/ai/transcription-model", {
      audio: Buffer.from(wav).toString("base64"), mediaType: "audio/wav", providerOptions: { azure: { timestamps: "word", transcribeStyle: "verbatim" } },
    }, { "ai-gateway-protocol-version": "0.0.1", "ai-transcription-model-specification-version": "4", "ai-model-id": this.config.models.transcription }, signal);
    const metadata = response.providerMetadata as { azure?: { phrases?: { words?: TimedWord[] }[] } } | undefined;
    const words = metadata?.azure?.phrases?.flatMap(p => p.words ?? []) ?? [];
    if (!words.length || words.length > 100000 || words.some(w => typeof w.text !== "string" || !Number.isFinite(w.offsetMilliseconds) || !Number.isFinite(w.durationMilliseconds) || w.offsetMilliseconds < 0 || w.durationMilliseconds < 0)) throw new APIError(502, "转录服务未返回有效时间轴");
    return words;
  }
}
