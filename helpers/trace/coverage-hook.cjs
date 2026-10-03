// Preloaded (NODE_OPTIONS=--require) into every server process and worker thread while
// generate-reach-map.sh records the e2e specs. SIGUSR2 to a process writes the V8
// coverage it gathered since the last signal to NODE_V8_COVERAGE and resets the counters;
// the main thread relays it to the process's worker threads, which get no signals.
const v8 = require('node:v8');
const { BroadcastChannel, isMainThread } = require('node:worker_threads');

const channel = new BroadcastChannel('enact-coverage');
channel.unref();
channel.onmessage = () => v8.takeCoverage();

if (isMainThread) {
  process.on('SIGUSR2', () => {
    v8.takeCoverage();
    channel.postMessage('take');
  });
}
