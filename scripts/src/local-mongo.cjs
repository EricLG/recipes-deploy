// Internal helper: dependencies and configuration belong to recipes-back.
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const backend = path.resolve(__dirname, '../../../recipes-back');
const load = createRequire(path.join(backend, 'package.json'));
const dotenv = load('dotenv');
const mongoose = load('mongoose');

async function main() {
  const config = dotenv.parse(fs.readFileSync(path.join(backend, '.env')));
  const uri = config.MONGODB_URI;
  const parsed = new URL(uri);
  if (parsed.protocol !== 'mongodb:' || !['localhost', '127.0.0.1', '[::1]'].includes(parsed.hostname)) {
    throw new Error('Only a single loopback MongoDB server is allowed');
  }
  const database = decodeURIComponent(parsed.pathname.slice(1));
  if (!database || ['admin', 'config', 'local'].includes(database)) throw new Error('Invalid application database');
  // Reject URI options able to override the explicit local target/database.
  if ([...parsed.searchParams.keys()].some(key => !['authSource', 'authMechanism', 'directConnection', 'serverSelectionTimeoutMS'].includes(key))) {
    throw new Error('Unsupported MongoDB URI option');
  }
  if (process.argv[2] === 'config') {
    process.stdout.write(JSON.stringify({ uri, database }));
    return;
  }
  await mongoose.connect(uri, { serverSelectionTimeoutMS: 5000, directConnection: true });
  try {
    if (process.argv[2] === 'drop') {
      await mongoose.connection.db.dropDatabase();
    } else if (process.argv[2] === 'inspect') {
      const collections = await mongoose.connection.db.listCollections().toArray();
      const counts = {};
      for (const collection of collections) {
        counts[collection.name] = await mongoose.connection.db.collection(collection.name).countDocuments();
      }
      const missingImages = [];
      for (const recipe of await mongoose.connection.db.collection('recipes').find().toArray()) {
        for (const value of Object.values(recipe)) {
          if (typeof value === 'string' && value.startsWith('/api/uploads/')) {
            const relative = value.slice('/api/uploads/'.length);
            const file = path.resolve(backend, 'uploads', relative);
            if (!file.startsWith(path.join(backend, 'uploads') + path.sep) || !fs.existsSync(file)) missingImages.push(value);
          }
        }
      }
      process.stdout.write(JSON.stringify({ database, counts, missingImages }));
    } else throw new Error('Unknown command');
  } finally {
    await mongoose.disconnect();
  }
}
main().catch(error => {
  // Never print the URI or credentials from driver errors.
  console.error(`Local MongoDB operation failed (${error.name})`);
  process.exitCode = 1;
});
