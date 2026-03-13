require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const generateRoutes = require('./routes/generate');
const creditsRoutes = require('./routes/credits');
const generationsRoutes = require('./routes/generations');
const authRoutes = require('./routes/auth');
const reelsRoutes = require('./routes/reels');
const avatarsRoutes = require('./routes/avatars');
const uploadsRoutes = require('./routes/uploads');
const influencerRoutes = require('./routes/influencer');
const modelsRoutes = require('./routes/models');
const createRoutes = require('./routes/create');

const app = express();
const PORT = process.env.PORT || 3001;

// Database
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

// Middleware
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use('/output', express.static('output'));

// Inject db into routes
app.use((req, res, next) => {
  req.db = pool;
  next();
});

// Routes
app.use('/api/generate', generateRoutes);
app.use('/api/credits', creditsRoutes);
app.use('/api/generations', generationsRoutes);
app.use('/api/auth', authRoutes);
app.use('/api/reels', reelsRoutes);
app.use('/api/avatars', avatarsRoutes);
app.use('/api/uploads', uploadsRoutes);
app.use('/api/influencer', influencerRoutes);
app.use('/api/models', modelsRoutes);
app.use('/api/create', createRoutes);
app.use('/uploads', express.static('uploads'));
app.use('/avatars', express.static('avatars'));

// Health check
app.get('/health', (req, res) => res.json({ status: 'ok', time: new Date().toISOString() }));

// Init DB tables & start
async function init() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      external_id TEXT UNIQUE,
      email TEXT,
      credits INTEGER DEFAULT 3,
      is_subscribed BOOLEAN DEFAULT false,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS generations (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      source_url TEXT,
      prompt TEXT,
      script JSONB,
      status TEXT DEFAULT 'pending',
      result_video_url TEXT,
      thumbnail_url TEXT,
      error TEXT,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS idx_generations_user ON generations(user_id);
    CREATE INDEX IF NOT EXISTS idx_generations_status ON generations(status);

    CREATE TABLE IF NOT EXISTS avatars (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      name TEXT DEFAULT 'Custom Avatar',
      gender TEXT DEFAULT 'neutral',
      style TEXT DEFAULT 'custom',
      source_image_url TEXT,
      thumbnail_url TEXT,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS video_uploads (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      filename TEXT,
      file_path TEXT,
      file_url TEXT,
      file_size BIGINT DEFAULT 0,
      duration FLOAT DEFAULT 0,
      width INT DEFAULT 0,
      height INT DEFAULT 0,
      fps INT DEFAULT 30,
      status TEXT DEFAULT 'ready',
      created_at TIMESTAMPTZ DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS ai_generations (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      model_id TEXT,
      mode TEXT,
      prompt TEXT,
      image_url TEXT,
      duration INT DEFAULT 5,
      replicate_id TEXT,
      status TEXT DEFAULT 'starting',
      output_url TEXT,
      error TEXT,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      completed_at TIMESTAMPTZ
    );

    CREATE INDEX IF NOT EXISTS idx_ai_gen_user ON ai_generations(user_id);
    CREATE INDEX IF NOT EXISTS idx_ai_gen_status ON ai_generations(status);

    CREATE TABLE IF NOT EXISTS avatar_uploads (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      name TEXT DEFAULT 'Custom Avatar',
      filename TEXT,
      file_url TEXT,
      file_size BIGINT DEFAULT 0,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS idx_avatars_user ON avatars(user_id);
    CREATE INDEX IF NOT EXISTS idx_uploads_user ON video_uploads(user_id);
    CREATE INDEX IF NOT EXISTS idx_avatar_uploads_user ON avatar_uploads(user_id);

    CREATE TABLE IF NOT EXISTS influencer_generations (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      avatar_id TEXT,
      reference_video_url TEXT,
      topic TEXT,
      duration INT DEFAULT 10,
      replicate_id TEXT,
      status TEXT DEFAULT 'starting',
      output_url TEXT,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      completed_at TIMESTAMPTZ
    );

    CREATE INDEX IF NOT EXISTS idx_influencer_generations_user ON influencer_generations(user_id);
    CREATE INDEX IF NOT EXISTS idx_influencer_generations_status ON influencer_generations(status);
  `);

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Creator AI Backend running on port ${PORT}`);
  });
}

init().catch(err => {
  console.error('Failed to start:', err);
  process.exit(1);
});
