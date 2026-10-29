// As server/test/medium/globalSetup.ts after its container is up: the specs clone the
// migrated `mich` template (enve's postgres postStart creates it) through
// IMMICH_TEST_POSTGRES_URL.
import { Kysely } from 'kysely';
import { ConfigRepository } from '../../src/repositories/config.repository.js';
import { DatabaseRepository } from '../../src/repositories/database.repository.js';
import { LoggingRepository } from '../../src/repositories/logging.repository.js';
import { DB } from '../../src/schema/index.js';
import { getKyselyConfig } from '../../src/utils/database.js';

const globalSetup = async () => {
  const postgresUrl = process.env.IMMICH_TEST_POSTGRES_URL;
  if (!postgresUrl) {
    throw new Error('IMMICH_TEST_POSTGRES_URL is not set (enve.cue profile environment)');
  }

  const db = new Kysely<DB>(getKyselyConfig({ connectionType: 'url', url: postgresUrl }));
  await new DatabaseRepository(db, LoggingRepository.create(), new ConfigRepository()).runMigrations();
  await db.destroy();
};

export default globalSetup;
