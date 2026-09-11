// Keep the development feedback loop focused on deterministic, low-latency
// contracts. Lifecycle, HTTP integration, and queue timing tests remain in
// run-tests.ts and are required by candidate/release validation.
import "./config.test.js";
import "./server-command.test.js";
import "./bridge-connection.test.js";
import "./security.test.js";
import "./event-journal.test.js";
import "./message-projection.test.js";
import "./timeline-projection.test.js";
import "./launcher-errors.test.js";
import "./worker-rpc.test.js";
import "./history-page.test.js";
