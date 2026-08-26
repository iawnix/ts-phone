import type { Readable } from "node:stream";
import { StringDecoder } from "node:string_decoder";

export interface JsonlReader {
  close(): void;
}

export function attachStrictJsonlReader(
  stream: Readable,
  onValue: (value: unknown) => void,
  onError: (error: Error) => void,
  maxRecordBytes: number,
): JsonlReader {
  const decoder = new StringDecoder("utf8");
  let buffer = "";
  let closed = false;

  const fail = (error: Error) => {
    if (!closed) onError(error);
  };
  const consume = () => {
    while (true) {
      const newlineIndex = buffer.indexOf("\n");
      if (newlineIndex < 0) break;
      let line = buffer.slice(0, newlineIndex);
      buffer = buffer.slice(newlineIndex + 1);
      if (line.endsWith("\r")) line = line.slice(0, -1);
      if (line.length === 0) continue;
      if (Buffer.byteLength(line) > maxRecordBytes) {
        fail(new Error("Bridge JSONL record exceeded the configured limit"));
        continue;
      }
      try {
        onValue(JSON.parse(line));
      } catch (error) {
        fail(new Error(`Invalid bridge JSONL record: ${(error as Error).message}`));
      }
    }
    if (Buffer.byteLength(buffer) > maxRecordBytes) {
      buffer = "";
      fail(new Error("Bridge JSONL record exceeded the configured limit"));
    }
  };
  const onData = (chunk: Buffer | string) => {
    buffer += typeof chunk === "string" ? chunk : decoder.write(chunk);
    consume();
  };
  const onEnd = () => {
    buffer += decoder.end();
    if (buffer.trim()) fail(new Error("Bridge stream ended with an unterminated JSONL record"));
  };
  const onStreamError = (error: Error) => fail(error);

  stream.on("data", onData);
  stream.on("end", onEnd);
  stream.on("error", onStreamError);
  return {
    close() {
      if (closed) return;
      closed = true;
      stream.off("data", onData);
      stream.off("end", onEnd);
      stream.off("error", onStreamError);
    },
  };
}
