const express = require('express');
const { Resend } = require('resend');
const { Webhook } = require('svix');
const router = express.Router();

const resend = new Resend(process.env.RESEND_API_KEY);
const RESEND_WEBHOOK_SECRET = process.env.RESEND_WEBHOOK_SECRET;

router.post(
    '/resend',
    express.raw({ type: 'application/json' }),
    async (req, res) => {
        const payload = req.body;
        const headers = req.headers;

        if (!RESEND_WEBHOOK_SECRET) {
            console.warn('⚠️ Missing RESEND_WEBHOOK_SECRET in environment variables.');
            return res.status(500).send('Server Configuration Error');
        }

        // 1. Verify the Webhook Signature
        const wh = new Webhook(RESEND_WEBHOOK_SECRET);
        let event;

        try {
            event = wh.verify(payload, headers);
        } catch (err) {
            console.error('⚠️ Webhook verification failed:', err.message);
            return res.status(400).send('Webhook Error: Invalid Signature');
        }

        if (event.type === 'email.received') {
            console.log('Received email webhook, attempting to forward...');

            try {
                const { data, error } = await resend.emails.receiving.forward({
                    emailId: event.data.email_id,
                    to: 'polskoydm@outlook.com', // Where you want to receive it
                    from: 'support@roamjet.net', // Must be a verified domain in your Resend account
                });

                if (error) {
                    console.error('Error forwarding email:', error);
                    return res.status(500).send(`Error: ${error.message}`);
                }

                console.log('Successfully forwarded email:', data);
                return res.status(200).json(data);
            } catch (err) {
                console.error('Exception forwarding email:', err);
                return res.status(500).send(`Exception: ${err.message}`);
            }
        }

        return res.status(200).json({});
    }
);

module.exports = router;
