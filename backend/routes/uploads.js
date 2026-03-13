/**
 * /api/uploads — Video upload for motion capture
 *
 * POST /api/uploads/video    → Upload a video file (multipart/form-data)
 * GET  /api/uploads/:id      → Get upload status + metadata
 * DELETE /api/uploads/:id    → Delete uploaded video
 */
const express = require('express');
const router = express.Router();
const { v4: uuid } = require('uuid');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');

// Storage config
const UPLOADS_DIR = path.join(__dirname, '..', 'uploads');
if (!fs.existsSync(UPLOADS_DIR)) fs.mkdirSync(UPLOADS_DIR, { recursive: true });

const storage = multer.diskStorage({
  destination: UPLOADS_DIR,
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || '.mp4';
    cb(null, uuid() + ext);
  }
});

const upload = multer({
  storage,
  limits: { fileSize: 100 * 1024 * 1024 }, // 100MB max
  fileFilter: (req, file, cb) => {
    const allowed = ['.mp4', '.mov', '.avi', '.webm', '.mkv'];
    const ext = path.extname(file.originalname).toLowerCase();
    if (allowed.includes(ext)) {
      cb(null, true);
    } else {
      cb(new Error('Only video files are allowed (mp4, mov, avi, webm, mkv)'));
    }
  }
});

// Extract video metadata with ffprobe
function getVideoMetadata(filepath) {
  try {
    const ffprobe = process.env.FFPROBE_PATH || 'ffprobe';
    const cmd = `${ffprobe} -v quiet -print_format json -show_format -show_streams "${filepath}"`;
    const output = execSync(cmd, { timeout: 10000 }).toString();
    const data = JSON.parse(output);
    const videoStream = (data.streams || []).find(s => s.codec_type === 'video');
    return {
      duration: parseFloat(data.format?.duration || 0),
      width: videoStream?.width || 0,
      height: videoStream?.height || 0,
      fps: videoStream?.r_frame_rate ? eval(videoStream.r_frame_rate) : 30,
      codec: videoStream?.codec_name || 'unknown',
      fileSize: parseInt(data.format?.size || 0)
    };
  } catch (e) {
    console.error('ffprobe error:', e.message);
    return { duration: 0, width: 0, height: 0, fps: 30, codec: 'unknown', fileSize: 0 };
  }
}

// POST /api/uploads/video — upload a video for motion capture
router.post('/video', upload.single('video'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No video file provided' });
  }

  const userId = req.body.userId;
  const id = uuid();
  const filePath = req.file.path;
  const fileUrl = `/uploads/${req.file.filename}`;

  try {
    // Get video metadata
    const meta = getVideoMetadata(filePath);

    // Validate duration (max 60 seconds for motion capture)
    if (meta.duration > 60) {
      fs.unlinkSync(filePath);
      return res.status(400).json({ error: 'Video must be 60 seconds or less for motion capture' });
    }

    // Save to DB
    await req.db.query(
      `INSERT INTO video_uploads (id, user_id, filename, file_path, file_url, file_size, duration, width, height, fps, status, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'ready', NOW())`,
      [id, userId || null, req.file.originalname, filePath, fileUrl, meta.fileSize, meta.duration, meta.width, meta.height, meta.fps]
    );

    console.log(`📹 Video uploaded: ${id} (${meta.duration.toFixed(1)}s, ${meta.width}x${meta.height})`);

    res.json({
      id,
      url: fileUrl,
      filename: req.file.originalname,
      duration: meta.duration,
      width: meta.width,
      height: meta.height,
      fps: Math.round(meta.fps),
      fileSize: meta.fileSize,
      status: 'ready'
    });
  } catch (err) {
    console.error('Upload error:', err.message);
    if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
    res.status(500).json({ error: 'Failed to process upload' });
  }
});

// GET /api/uploads/:id
router.get('/:id', async (req, res) => {
  try {
    const result = await req.db.query('SELECT * FROM video_uploads WHERE id = $1', [req.params.id]);
    if (!result.rows.length) return res.status(404).json({ error: 'Upload not found' });
    const r = result.rows[0];
    res.json({
      id: r.id,
      url: r.file_url,
      filename: r.filename,
      duration: r.duration,
      width: r.width,
      height: r.height,
      fps: r.fps,
      fileSize: r.file_size,
      status: r.status,
      createdAt: r.created_at
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed to get upload' });
  }
});

// GET /api/uploads/user/:userId — list uploads for a user
router.get('/user/:userId', async (req, res) => {
  try {
    const result = await req.db.query(
      'SELECT * FROM video_uploads WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50',
      [req.params.userId]
    );
    res.json({
      uploads: result.rows.map(r => ({
        id: r.id,
        url: r.file_url,
        filename: r.filename,
        duration: r.duration,
        width: r.width,
        height: r.height,
        status: r.status,
        createdAt: r.created_at
      }))
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed to list uploads' });
  }
});

// DELETE /api/uploads/:id
router.delete('/:id', async (req, res) => {
  try {
    const result = await req.db.query('SELECT file_path FROM video_uploads WHERE id = $1', [req.params.id]);
    if (result.rows.length && result.rows[0].file_path) {
      const fp = result.rows[0].file_path;
      if (fs.existsSync(fp)) fs.unlinkSync(fp);
    }
    await req.db.query('DELETE FROM video_uploads WHERE id = $1', [req.params.id]);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: 'Failed to delete upload' });
  }
});

module.exports = router;
