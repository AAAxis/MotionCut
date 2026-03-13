const express = require('express');
const router = express.Router();

// POST /api/generations/list
router.post('/list', async (req, res) => {
  const { userId, limit = 50 } = req.body;
  if (!userId) return res.status(400).json({ error: 'userId required' });

  const result = await req.db.query(
    `SELECT id, user_id as "userId", source_url as "sourceUrl", prompt,
            status, result_video_url as "resultVideoUrl",
            thumbnail_url as "thumbnailUrl", script, error,
            created_at as "createdAt"
     FROM generations
     WHERE user_id = $1
     ORDER BY created_at DESC
     LIMIT $2`,
    [userId, limit]
  );

  res.json({ generations: result.rows });
});

// POST /api/generations/update — webhook callback for external processors
router.post('/update', async (req, res) => {
  const { generationId, status, resultVideoUrl, thumbnailUrl, error } = req.body;
  if (!generationId) return res.status(400).json({ error: 'generationId required' });

  const updates = [];
  const values = [];
  let idx = 1;

  if (status) { updates.push(`status = $${idx++}`); values.push(status); }
  if (resultVideoUrl) { updates.push(`result_video_url = $${idx++}`); values.push(resultVideoUrl); }
  if (thumbnailUrl) { updates.push(`thumbnail_url = $${idx++}`); values.push(thumbnailUrl); }
  if (error) { updates.push(`error = $${idx++}`); values.push(error); }
  updates.push(`updated_at = NOW()`);

  values.push(generationId);

  await req.db.query(
    `UPDATE generations SET ${updates.join(', ')} WHERE id = $${idx}`,
    values
  );

  res.json({ ok: true });
});

module.exports = router;
