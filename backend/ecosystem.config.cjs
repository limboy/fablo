const path = require("node:path");

const common = {
  cwd: __dirname,
  // Launch Bun directly so PM2's Bun loader cannot bypass import.meta.main.
  interpreter: "none",
  exec_mode: "fork",
  instances: 1,
  autorestart: true,
  watch: false,
  time: true,
  restart_delay: 2000,
  kill_timeout: 15000,
  env: { NODE_ENV: "production" },
};

module.exports = {
  apps: [
    { ...common, name: "fablo", script: process.env.BUN_BIN || "bun", args: [path.join(__dirname, "src/server.ts")], max_memory_restart: "1G" },
  ],
};
