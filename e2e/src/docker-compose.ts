import { exec, spawn } from 'node:child_process';
import { setTimeout } from 'node:timers';

const setup = async () => {
  if (
    process.env.VITEST_DISABLE_DOCKER_SETUP === 'true' ||
    process.env.IMMICH_TEST_POSTGRES_URL ||
    process.env.IMMICH_SERVER_URL ||
    process.env.CI
  ) {
    console.log('✓ Zero-docker enve environment active: skipping docker compose');
    return async () => {};
  }

  let _resolve: () => unknown;
  let _reject: (error: Error) => unknown;

  const ready = new Promise<void>((resolve, reject) => {
    _resolve = resolve;
    _reject = reject;
  });

  const timeout = setTimeout(() => _reject(new Error('Timeout starting e2e environment')), 60_000);

  const command = 'compose up --build --renew-anon-volumes --force-recreate --remove-orphans';
  const child = spawn('docker', command.split(' '), { stdio: 'pipe' });

  child.stdout.on('data', (data) => {
    const input = data.toString();
    console.log(input);
    if (input.includes('Immich Microservices is running')) {
      _resolve();
    }
  });

  child.stderr.on('data', (data) => console.log(data.toString()));

  await ready;
  clearTimeout(timeout);

  return async () => {
    await new Promise<void>((resolve) => exec('docker compose down', () => resolve()));
  };
};

export default setup;
