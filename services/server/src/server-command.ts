export const SERVER_USAGE = `Usage:\n  ts-phone-server\n\nStarts the local TS Phone server using TS_PHONE_* environment variables.\n`;

export type ServerCommand = "start" | "help";

export function parseServerCommand(arguments_: readonly string[]): ServerCommand {
  if (arguments_.length === 0) return "start";
  if (
    arguments_.length === 1
    && (arguments_[0] === "help" || arguments_[0] === "--help" || arguments_[0] === "-h")
  ) {
    return "help";
  }
  throw new Error("ts-phone-server does not accept positional arguments or runtime options");
}
